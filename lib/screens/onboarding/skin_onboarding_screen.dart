import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/skin_profile.dart';
import '../../utils/app_prefs.dart';
import 'widgets/skin_onboarding_widgets.dart';

class SkinOnboardingScreen extends StatefulWidget {
  const SkinOnboardingScreen({super.key});

  @override
  State<SkinOnboardingScreen> createState() => _SkinOnboardingScreenState();
}

class _SkinOnboardingScreenState extends State<SkinOnboardingScreen> {
  static const int _totalSteps = 7;

  final PageController _pageController = PageController();
  final TextEditingController _routineProductController =
      TextEditingController();
  final TextEditingController _favoriteIngredientController =
      TextEditingController();
  final TextEditingController _ingredientToAvoidController =
      TextEditingController();
  final TextEditingController _otherProductPreferenceController =
      TextEditingController();
  final TextEditingController _procedureNameController =
      TextEditingController();
  final TextEditingController _procedureOutcomeController =
      TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _climateController = TextEditingController();
  final TextEditingController _humidityController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  int _currentStep = 0;
  bool _saving = false;
  final Set<SkinType> _selectedSkinTypes = <SkinType>{};
  SensitivityLevel? _sensitivityLevel;
  DateTime? _selectedProcedureDate;
  final Set<String> _mainConcerns = <String>{};
  final Set<String> _goals = <String>{};
  final Set<String> _selectedProductPreferences = <String>{};
  final Set<String> _favoriteIngredients = <String>{};
  final Set<String> _ingredientsToAvoid = <String>{};
  final Map<String, Set<String>> _routine = <String, Set<String>>{
    'Morning': <String>{},
    'Evening': <String>{},
    'Weekly / As Needed': <String>{},
  };
  final List<SkinProcedureHistoryEntry> _pastProcedures =
      <SkinProcedureHistoryEntry>[];

  @override
  void dispose() {
    _pageController.dispose();
    _routineProductController.dispose();
    _favoriteIngredientController.dispose();
    _ingredientToAvoidController.dispose();
    _otherProductPreferenceController.dispose();
    _procedureNameController.dispose();
    _procedureOutcomeController.dispose();
    _locationController.dispose();
    _climateController.dispose();
    _humidityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastStep = _currentStep == _totalSteps - 1;

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingHeader(
              currentStep: _currentStep,
              totalSteps: _totalSteps,
              onSkip: _saving ? null : () => _saveAndExit(isSkipped: true),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentStep = index),
                children: [
                  WelcomeSkinTypeStep(
                    selectedSkinTypes: _selectedSkinTypes,
                    onToggle: (type) => setState(() {
                      if (_selectedSkinTypes.contains(type)) {
                        _selectedSkinTypes.remove(type);
                      } else if (_selectedSkinTypes.length <
                          WelcomeSkinTypeStep.maxSelection) {
                        _selectedSkinTypes.add(type);
                      }
                    }),
                  ),
                  SensitivityStep(
                    selectedLevel: _sensitivityLevel,
                    onChanged: (value) =>
                        setState(() => _sensitivityLevel = value),
                  ),
                  MainConcernsStep(
                    selectedConcerns: _mainConcerns,
                    onToggle: _toggleConcern,
                  ),
                  PastProceduresStep(
                    procedures: _pastProcedures,
                    procedureNameController: _procedureNameController,
                    procedureOutcomeController: _procedureOutcomeController,
                    selectedProcedureDate: _selectedProcedureDate,
                    onPickDate: _pickProcedureDate,
                    onAddProcedure: _addProcedure,
                    onRemoveProcedure: _removeProcedure,
                  ),
                  EnvironmentStep(
                    locationController: _locationController,
                    climateController: _climateController,
                    humidityController: _humidityController,
                  ),
                  GoalsFinalStep(
                    selectedGoals: _goals,
                    onToggleGoal: _toggleGoal,
                    notesController: _notesController,
                  ),
                  CurrentRoutineStep(
                    routine: _routine,
                    productController: _routineProductController,
                    selectedPreferences: _selectedProductPreferences,
                    otherPreferenceController:
                        _otherProductPreferenceController,
                    favoriteIngredientController: _favoriteIngredientController,
                    ingredientToAvoidController: _ingredientToAvoidController,
                    favoriteIngredients: _favoriteIngredients,
                    ingredientsToAvoid: _ingredientsToAvoid,
                    onAddProduct: _addRoutineProduct,
                    onRemoveProduct: _removeRoutineProduct,
                    onPreferenceToggle: _toggleProductPreference,
                    onAddFavoriteIngredient: _addFavoriteIngredient,
                    onRemoveFavoriteIngredient: _removeFavoriteIngredient,
                    onAddIngredientToAvoid: _addIngredientToAvoid,
                    onRemoveIngredientToAvoid: _removeIngredientToAvoid,
                  ),
                ],
              ),
            ),
            _OnboardingFooter(
              canGoBack: _currentStep > 0 && !_saving,
              canGoNext:
                  _currentStep != 0 || _selectedSkinTypes.isNotEmpty,
              isLastStep: isLastStep,
              saving: _saving,
              onBack: _goBack,
              onNext: isLastStep ? () => _saveAndExit() : _goNext,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleConcern(String concern) {
    setState(() {
      if (!_mainConcerns.add(concern)) {
        _mainConcerns.remove(concern);
      }
    });
  }

  void _toggleGoal(String goal) {
    setState(() {
      if (!_goals.add(goal)) {
        _goals.remove(goal);
      }
    });
  }

  void _addRoutineProduct(String rawProduct) {
    final product = rawProduct.trim();
    if (product.isEmpty) return;

    setState(() {
      _routine['Morning']!.add(product);
      _routine['Evening']!.add(product);
      _routineProductController.clear();
    });
  }

  void _removeRoutineProduct(String section, String product) {
    setState(() => _routine[section]?.remove(product));
  }

  void _toggleProductPreference(String preference) {
    setState(() {
      if (_selectedProductPreferences.contains(preference)) {
        _selectedProductPreferences.remove(preference);
      } else if (_selectedProductPreferences.length <
          CurrentRoutineStep.maxPreferenceSelection) {
        _selectedProductPreferences.add(preference);
      }
    });
  }

  void _addFavoriteIngredient(String rawIngredient) {
    final ingredient = rawIngredient.trim();
    if (ingredient.isEmpty) return;

    setState(() {
      _favoriteIngredients.add(ingredient);
      _favoriteIngredientController.clear();
    });
  }

  void _removeFavoriteIngredient(String ingredient) {
    setState(() => _favoriteIngredients.remove(ingredient));
  }

  void _addIngredientToAvoid(String rawIngredient) {
    final ingredient = rawIngredient.trim();
    if (ingredient.isEmpty) return;

    setState(() {
      _ingredientsToAvoid.add(ingredient);
      _ingredientToAvoidController.clear();
    });
  }

  void _removeIngredientToAvoid(String ingredient) {
    setState(() => _ingredientsToAvoid.remove(ingredient));
  }

  Future<void> _pickProcedureDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedProcedureDate ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.champagneGold,
              onPrimary: AppColors.onChampagneGold,
              surface: AppColors.cardBackground,
              onSurface: AppColors.refinedSlate,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    setState(() => _selectedProcedureDate = picked);
  }

  void _addProcedure() {
    final name = _procedureNameController.text.trim();
    final outcome = _procedureOutcomeController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _pastProcedures.add(
        SkinProcedureHistoryEntry(
          procedureName: name,
          date: _selectedProcedureDate,
          outcome: outcome,
        ),
      );
      _procedureNameController.clear();
      _procedureOutcomeController.clear();
      _selectedProcedureDate = null;
    });
  }

  void _removeProcedure(int index) {
    setState(() => _pastProcedures.removeAt(index));
  }

  void _goNext() {
    if (_currentStep >= _totalSteps - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _goBack() {
    if (_currentStep == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveAndExit({bool isSkipped = false}) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final profile = _buildProfile(isSkipped: isSkipped);
      await AppPrefs.saveSkinProfile(
        profile,
        markOnboardingComplete: !isSkipped,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/welcome-tour');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your skin profile. Please try again.'),
        ),
      );
    }
  }

  /// Derives the single canonical SkinType from the multi-selection.
  /// Used by the json-serializable SkinProfile which stores one primary type.
  SkinType get _primarySkinType {
    if (_selectedSkinTypes.isEmpty) return SkinType.normal;
    if (_selectedSkinTypes.length == 1) return _selectedSkinTypes.first;
    if (_selectedSkinTypes.contains(SkinType.combination)) {
      return SkinType.combination;
    }
    if (_selectedSkinTypes.contains(SkinType.dry) &&
        _selectedSkinTypes.contains(SkinType.oily)) {
      return SkinType.combination;
    }
    // Prefer the first non-sensitive type so sensitive stays an additive signal
    return _selectedSkinTypes.firstWhere(
      (t) => t != SkinType.sensitive,
      orElse: () => SkinType.sensitive,
    );
  }

  SkinProfile _buildProfile({required bool isSkipped}) {
    final routine = _routine.map(
      (section, products) =>
          MapEntry(section, products.toList(growable: false)),
    );
    routine.removeWhere((_, products) => products.isEmpty);

    // Encode secondary skin types into notes so the AI coach can leverage all
    // selected types even though SkinProfile stores only a single primary type.
    final skinTypesNote = _selectedSkinTypes.length > 1
        ? '[skin_types: ${_selectedSkinTypes.map(skinTypeLabel).join(', ')}]'
        : '';

    final notes = [
      if (skinTypesNote.isNotEmpty) skinTypesNote,
      _notesController.text.trim(),
      if (isSkipped) AppPrefs.skinProfileSkippedNote,
    ].where((note) => note.isNotEmpty).join('\n');

    return SkinProfile(
      skinType: _primarySkinType,
      sensitivityLevel: _sensitivityLevel ?? SensitivityLevel.moderate,
      mainConcerns: _mainConcerns.toList(growable: false),
      currentRoutine: routine,
      productPreference: _normalizedProductPreference,
      favoriteIngredients: _favoriteIngredients.toList(growable: false),
      ingredientsToAvoid: _ingredientsToAvoid.toList(growable: false),
      pastProcedures: List<SkinProcedureHistoryEntry>.from(_pastProcedures),
      location: _locationController.text.trim(),
      climate: _climateController.text.trim(),
      humidity: _humidityController.text.trim(),
      goals: _goals.toList(growable: false),
      notes: notes,
      updatedAt: DateTime.now(),
    );
  }

  String get _normalizedProductPreference {
    if (_selectedProductPreferences.isEmpty) return '';
    final prefs = _selectedProductPreferences.toList()..sort();
    final preferences = prefs.map((p) {
      if (p == 'other') {
        final other = _otherProductPreferenceController.text.trim();
        return other.isEmpty ? 'other' : 'other: $other';
      }
      return p;
    }).toList();
    return preferences.join('; ');
  }
}

class _OnboardingHeader extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onSkip;

  const _OnboardingHeader({
    required this.currentStep,
    required this.totalSteps,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (currentStep + 1) / totalSteps;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Skin Profile',
                  style: TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSkip,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: AppColors.cardBackground,
              color: AppColors.champagneGold,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Step ${currentStep + 1} of $totalSteps',
              style: TextStyle(
                color: AppColors.refinedSlate.withValues(alpha: 0.58),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  final bool canGoBack;
  final bool canGoNext;
  final bool isLastStep;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _OnboardingFooter({
    required this.canGoBack,
    this.canGoNext = true,
    required this.isLastStep,
    required this.saving,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.warmAlabaster.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: AppColors.borders.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: canGoBack ? onBack : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                foregroundColor: AppColors.refinedSlate,
                side: BorderSide(
                  color: AppColors.champagneGold.withValues(alpha: 0.42),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: saving || !canGoNext ? null : onNext,
              style: MyApp.primaryGoldButton,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isLastStep ? 'Save Profile' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}
