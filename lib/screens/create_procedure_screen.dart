import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../models/procedure.dart';
import '../models/provider_directory.dart';
import '../utils/app_prefs.dart';
import '../utils/procedure_focus_area.dart';
import 'procedure_profiles_screen.dart';
import 'provider_directory_screen.dart';

/// Curated suggestions for the Provider / Clinic autocomplete.
const List<String> _kKnownClinics = <String>[
  'Premier Aesthetics',
  'SkinSpirit',
  'LaserAway',
  'Ideal Image',
  'Skin Laundry',
  'Heyday',
  'Sono Bello',
  'Allergan Aesthetics',
  'Allure Aesthetic Surgery',
  'Westlake Dermatology',
  'Schweiger Dermatology',
  'Russak Dermatology',
  'Tribeca MedSpa',
  'Skinney MedSpa',
  'Smooth Synergy',
  'Dr. Smith Clinic',
  'Dr. Lee Aesthetic Clinic',
  'Dr. Patel Dermatology',
  'Beverly Hills Aesthetics',
  'Manhattan Dermatology',
  'Miami Skin Institute',
  'Houston Aesthetic Center',
  'Chicago Plastic Surgery',
  'Toronto MedSpa',
  'London Aesthetic Clinic',
];

const Set<String> injectableProcedureTypes = {
  'Botox / Dysport / Xeomin',
  'Dermal Fillers',
  'Lip Augmentation',
};

const Set<String> cosmeticSurgeryProcedureTypes = {
  'BBL',
  'Liposuction',
  'Tummy Tuck',
  'Arm Contouring',
  'Thigh Lift',
  'Hair Transplant',
  'Rhinoplasty',
  'Blepharoplasty',
  'Facelift',
  'Neck Lift',
  'Brow Lift',
  'Chin / Jawline Contouring',
  'Buccal Fat Removal',
};

const List<String> medicalAestheticProcedureTypes = [
  'Halo Laser',
  'Microneedling',
  'RF Microneedling',
  'Fractional Laser',
  'CO2 Laser Resurfacing',
  'IPL',
  'Chemical Peel',
  'Morpheus8',
  'Other',
];

const List<String> cosmeticProcedureTypes = [
  'Botox / Dysport / Xeomin',
  'Dermal Fillers',
  'Lip Augmentation',
  'Thread Lift',
  'BBL',
  'Liposuction',
  'Tummy Tuck',
  'Arm Contouring',
  'Thigh Lift',
  'Hair Transplant',
  'Rhinoplasty',
  'Blepharoplasty',
  'Facelift',
  'Neck Lift',
  'Brow Lift',
  'Chin / Jawline Contouring',
  'Buccal Fat Removal',
  'Other',
];

const List<String> atHomeProcedureTypes = [
  'At-Home Microneedling (RF)',
  'At-Home Microneedling (SkinPen)',
  'At-Home Chemical Peel',
  'Red Light Therapy',
  'Blue Light Therapy',
  'LED Light Therapy',
  'GHK-Cu Serum Session',
  'At-Home Dermaplaning',
  'Other',
];

const String medicalAestheticCategory = 'Medical Procedures';
const String cosmeticCategory = 'Cosmetic Procedures';
const String atHomeCategory = 'At-Home Procedures';

List<String> buildProcedureBarrierRecoveryReminders(String procedureType) {
  final canonicalType = canonicalProcedureType(procedureType);

  if (injectableProcedureTypes.contains(canonicalType)) {
    return [
      'Use a cool compress as needed during the first 24 hours',
      'Avoid strenuous exercise, saunas, and facials for 24 hours',
      'Avoid rubbing or massaging the treated area unless your provider instructed it',
      'Use broad-spectrum SPF 50+ every morning',
    ];
  }

  if (canonicalType == 'Thread Lift') {
    return [
      'Sleep elevated and avoid pressure on the treated area',
      'Avoid exaggerated facial movements for several days',
      'Avoid retinoids, acids, and exfoliants until irritation has fully settled',
      'Use broad-spectrum SPF 50+ every morning',
    ];
  }

  if (canonicalType == 'BBL') {
    return [
      'Avoid sitting directly on the area until your surgeon clears it',
      'Wear your compression garment exactly as instructed',
      'Sleep in positions that keep pressure off the grafted area',
      'Stay hydrated and follow all post-op movement guidance',
    ];
  }

  if (cosmeticSurgeryProcedureTypes.contains(canonicalType)) {
    return [
      'Cleanse gently and follow your surgeon\'s wound-care instructions exactly',
      'Sleep elevated and avoid pressure on the treatment area',
      'Avoid retinoids, acids, exfoliants, and active irritation until fully cleared',
      'Use broad-spectrum SPF 50+ every morning once approved by your provider',
    ];
  }

  return [
    'Apply gentle moisturizer twice daily',
    'Avoid retinoids and acids for 7 days',
    'Use broad-spectrum SPF 50+ every morning',
  ];
}

class CreateProcedureScreen extends StatefulWidget {
  final Procedure? initialProcedure;

  const CreateProcedureScreen({super.key, this.initialProcedure});

  @override
  State<CreateProcedureScreen> createState() => _CreateProcedureScreenState();
}

class _CreateProcedureScreenState extends State<CreateProcedureScreen> {
  final procedureTypes = const [
    ...medicalAestheticProcedureTypes,
    ...cosmeticProcedureTypes,
    ...atHomeProcedureTypes,
  ];

  String selectedCategory = medicalAestheticCategory;
  String? selectedType;
  String? selectedFocusArea;
  bool _focusAreaUserEdited = false;
  late DateTime selectedDate;
  late int numSessions;
  late final TextEditingController _providerController;
  late final TextEditingController _notesController;
  late final TextEditingController _customProcedureController;
  late final TextEditingController _customDescriptionController;
  Provider? _selectedProvider;
  bool _manualEntryExpanded = false;
  bool _isSubmitting = false;

  bool get _isEditing => widget.initialProcedure != null;
  bool get _isAtHome => selectedCategory == atHomeCategory;
  bool get _isOtherSelected => selectedType == 'Other';
  bool get _isOtherFocusArea =>
      selectedFocusArea?.trim().toLowerCase() == 'other';
  bool get _usesBodyFocusAreas => usesBodyFocusAreas(_effectiveProcedureType());
  bool get _requiresFocusArea => _focusAreaOptions.isNotEmpty;
  bool get _hasFocusAreaSelection => _focusAreaForSave != null;
  List<String> get _visibleProcedureTypes => switch (selectedCategory) {
    cosmeticCategory => cosmeticProcedureTypes,
    atHomeCategory => atHomeProcedureTypes,
    _ => medicalAestheticProcedureTypes,
  };
  bool get _showsSessionField {
    final procedureType = _effectiveProcedureType();
    if (procedureType.isEmpty && _isOtherSelected) {
      return true;
    }
    return supportsMultipleSessions(procedureType);
  }

  String _defaultProcedureTypeForCategory(String category) {
    final options = switch (category) {
      cosmeticCategory => cosmeticProcedureTypes,
      atHomeCategory => atHomeProcedureTypes,
      _ => medicalAestheticProcedureTypes,
    };
    return options.firstWhere((type) => type != 'Other', orElse: () => 'Other');
  }

  String _categoryForProcedureType(String procedureType) {
    if ((widget.initialProcedure?.category.trim().isNotEmpty ?? false) &&
        procedureType.trim() == (widget.initialProcedure?.type.trim() ?? '')) {
      return widget.initialProcedure!.category.trim();
    }

    final canonicalType = canonicalProcedureType(procedureType);
    if (atHomeProcedureTypes.contains(canonicalType) &&
        canonicalType != 'Other') {
      return atHomeCategory;
    }
    if (cosmeticProcedureTypes.contains(canonicalType) &&
        canonicalType != 'Other') {
      return cosmeticCategory;
    }
    return inferProcedureCategory(procedureType) == cosmeticCategory
        ? cosmeticCategory
        : medicalAestheticCategory;
  }

  void _selectCategory(String category) {
    setState(() {
      selectedCategory = category;
      if (selectedType == null) {
        selectedType = _defaultProcedureTypeForCategory(category);
      } else if (!_visibleProcedureTypes.contains(selectedType)) {
        selectedType = _defaultProcedureTypeForCategory(category);
        _customProcedureController.clear();
        selectedFocusArea = null;
        _focusAreaUserEdited = false;
      }
      if (!_showsSessionField) {
        numSessions = 1;
      } else if (numSessions < 1) {
        numSessions = 1;
      }
      _refreshFocusAreaForProcedureChange();
    });
  }

  String _effectiveProcedureType() {
    if (_isOtherSelected) return _customProcedureController.text.trim();
    return (selectedType ?? '').trim();
  }

  List<String> get _focusAreaOptions {
    return focusAreasForProcedure(_effectiveProcedureType());
  }

  String get _defaultFocusArea {
    return defaultFocusAreaForProcedure(_effectiveProcedureType());
  }

  String? get _focusAreaForSave {
    final focusArea = selectedFocusArea?.trim();
    return focusArea == null || focusArea.isEmpty ? null : focusArea;
  }

  String? get _customDescriptionForSave {
    return normalizedCustomDescription(_customDescriptionController.text);
  }

  void _applyDefaultFocusArea({bool force = false}) {
    if (_focusAreaUserEdited && !force) return;
    final options = _focusAreaOptions;
    if (options.isEmpty) {
      selectedFocusArea = null;
      return;
    }
    if (!force &&
        selectedFocusArea != null &&
        options.contains(selectedFocusArea)) {
      return;
    }
    var next = _defaultFocusArea;
    if (!options.contains(next)) next = options.first;
    selectedFocusArea = next;
  }

  void _refreshFocusAreaForProcedureChange() {
    final options = _focusAreaOptions;
    if (selectedFocusArea != null && !options.contains(selectedFocusArea)) {
      selectedFocusArea = null;
      _focusAreaUserEdited = false;
    }
    _applyDefaultFocusArea();
  }

  Future<void> _createProcedure() async {
    if (_isSubmitting) return;

    final notes = _notesController.text.trim();
    final procedureType = _effectiveProcedureType();
    final provider = _isAtHome
        ? 'Self / At-Home'
        : _providerController.text.trim();

    if (procedureType.isEmpty || provider.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    if (_requiresFocusArea && !_hasFocusAreaSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a focus area')),
      );
      return;
    }

    if (_isOtherFocusArea && _customDescriptionForSave == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the focus area')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final newProcedure = Procedure(
      id: 'proc_${DateTime.now().microsecondsSinceEpoch}',
      type: procedureType,
      category: selectedCategory,
      provider: provider,
      startDate: selectedDate,
      numSessions: _showsSessionField ? numSessions : 1,
      focusArea: _focusAreaForSave,
      customDescription: _customDescriptionForSave,
      notes: notes,
      customReminders: [
        ...buildProcedureBarrierRecoveryReminders(procedureType),
        'Apply SPF 50+ daily',
      ],
      milestoneDates: [
        selectedDate.add(const Duration(days: 7)),
        selectedDate.add(const Duration(days: 30)),
      ],
    );

    try {
      final entries = await AppPrefs.getProcedureEntries();
      final updated = List<Map<String, dynamic>>.from(entries);

      // FIXED: Explicitly add plannedSessions as a number so home screen no longer shows "Unknown sessions"
      final procedureJson = newProcedure.toJson();
      procedureJson['plannedSessions'] = _showsSessionField ? numSessions : 1;

      updated.add(procedureJson);
      await AppPrefs.saveProcedureHistory(updated);
      await AppPrefs.setSelectedProcedureId(newProcedure.id);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Procedure created successfully'),
          duration: Duration(milliseconds: 900),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProcedureDetailScreen(procedure: newProcedure),
          settings: RouteSettings(name: '/procedures/${newProcedure.id}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save procedure: $e'),
          backgroundColor: AppColors.softTerracotta,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    final existing = widget.initialProcedure;
    final existingType = (existing?.type ?? '').trim();

    selectedCategory = existingType.isEmpty
        ? medicalAestheticCategory
        : _categoryForProcedureType(existingType);

    selectedType = procedureTypes.contains(existingType)
        ? existingType
        : (existingType.isEmpty ? null : 'Other');

    selectedDate = existing?.startDate ?? DateTime.now();
    final existingSupportsMultipleSessions = existing == null
        ? false
        : supportsMultipleSessions(existing.type);
    numSessions =
        existing?.numSessions ?? (existingSupportsMultipleSessions ? 3 : 1);

    _providerController = TextEditingController(text: existing?.provider ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _customProcedureController = TextEditingController(
      text: procedureTypes.contains(existingType) ? '' : existingType,
    );
    _customDescriptionController = TextEditingController(
      text: existing?.customDescription ?? '',
    );
    selectedFocusArea = existing?.focusArea;
    _applyDefaultFocusArea();
    // If we're editing and the provider already has text, expand the
    // manual section so the user can see / edit it.
    if ((existing?.provider ?? '').trim().isNotEmpty) {
      _manualEntryExpanded = true;
    }
  }

  @override
  void dispose() {
    _providerController.dispose();
    _notesController.dispose();
    _customProcedureController.dispose();
    _customDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const textColor = AppColors.refinedSlate;

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: _isEditing ? 'Edit Procedure' : 'New Procedure',
          eyebrow: 'Treatment plan',
          color: textColor,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          color: textColor,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 22),

            // ===== Category (visual cards) =====
            _fieldLabel('Procedure Category', required: true),
            const SizedBox(height: 8),
            _buildCategoryCards(),
            const SizedBox(height: 6),
            Text(
              _categoryDescription(selectedCategory),
              style: TextStyle(
                color: textColor.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 18),

            // ===== Procedure Type =====
            _fieldLabel('Procedure Type', required: true),
            const SizedBox(height: 6),
            _buildTypeDropdown(),

            if (_isOtherSelected) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customProcedureController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (!_showsSessionField && numSessions != 1) {
                    setState(() {
                      numSessions = 1;
                      selectedFocusArea = null;
                      _focusAreaUserEdited = false;
                      _refreshFocusAreaForProcedureChange();
                    });
                  } else {
                    setState(() {
                      selectedFocusArea = null;
                      _focusAreaUserEdited = false;
                      _refreshFocusAreaForProcedureChange();
                    });
                  }
                },
                decoration: _decoration(
                  hint: 'Enter custom procedure name',
                  icon: Icons.edit_outlined,
                ),
              ),
            ],

            const SizedBox(height: 18),

            // ===== Focus Area =====
            _fieldLabel('Focus Area', required: true),
            const SizedBox(height: 6),
            _buildFocusAreaCard(),

            if (_isOtherSelected && !_isOtherFocusArea) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customDescriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 140,
                decoration: _decoration(
                  hint: 'Short description, e.g. fat transfer to hips',
                  icon: Icons.notes_rounded,
                ),
              ),
            ],

            // ===== Provider / Clinic (not applicable for At-Home) =====
            if (!_isAtHome) ...[
              const SizedBox(height: 18),
              _fieldLabel('Provider / Clinic', required: true),
              const SizedBox(height: 6),
              _buildProviderSection(textColor),
            ],

            const SizedBox(height: 18),

            // ===== Start Date =====
            _fieldLabel('Start date', required: true),
            const SizedBox(height: 6),
            _buildDateTile(),

            if (_showsSessionField) ...[
              const SizedBox(height: 18),
              _fieldLabel('Planned number of sessions', required: true),
              const SizedBox(height: 6),
              _buildSessionStepper(),
            ],

            const SizedBox(height: 18),

            // ===== Notes =====
            _fieldLabel('Notes', optional: true),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: _decoration(
                hint: 'Aftercare instructions, expectations, side effects…',
                icon: Icons.edit_note_rounded,
              ),
            ),

            const SizedBox(height: 32),

            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────── Helpers ───────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warmAlabaster,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.32),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.champagneGold.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.medical_services_outlined,
              color: AppColors.champagneGold,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing
                      ? 'Update procedure course'
                      : 'New procedure course',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isEditing
                      ? 'Refine details & schedule'
                      : 'Track your aesthetic treatment journey',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.refinedSlate.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(
    String label, {
    bool required = false,
    bool optional = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.refinedSlate,
            letterSpacing: 0.1,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              color: AppColors.softTerracotta,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        if (optional) ...[
          const SizedBox(width: 6),
          Text(
            'optional',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.refinedSlate.withValues(alpha: 0.45),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _decoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.refinedSlate.withValues(alpha: 0.46),
      ),
      prefixIcon: icon != null
          ? Icon(
              icon,
              color: AppColors.champagneGold.withValues(alpha: 0.82),
              size: 20,
            )
          : null,
      filled: true,
      fillColor: AppColors.cardBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borders),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borders),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.champagneGold,
          width: 1.4,
        ),
      ),
    );
  }

  Widget _buildCategoryCards() {
    return Row(
      children: [
        Expanded(
          child: _categoryCard(
            value: medicalAestheticCategory,
            title: 'Medical',
            subtitle: 'Resurfacing, collagen, lasers',
            icon: Icons.medical_services_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _categoryCard(
            value: cosmeticCategory,
            title: 'Cosmetic',
            subtitle: 'Botox, fillers, surgery',
            icon: Icons.auto_awesome_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _categoryCard(
            value: atHomeCategory,
            title: 'At-Home',
            subtitle: 'RF, SkinPen, LED',
            icon: Icons.home_repair_service_rounded,
          ),
        ),
      ],
    );
  }

  String _categoryDescription(String category) {
    return switch (category) {
      cosmeticCategory =>
        'Botox, fillers, professional peels, lifts, and cosmetic procedures.',
      atHomeCategory =>
        'RF microneedling, SkinPen, chemical peels, red/blue/LED light therapy, GHK-Cu, and dermaplaning.',
      _ =>
        'Resurfacing, collagen, lasers, injectables, surgery, and in-clinic medical treatments.',
    };
  }

  Widget _categoryCard({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = selectedCategory == value;
    return InkWell(
      onTap: () => _selectCategory(value),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    AppColors.champagneGold.withValues(alpha: 0.18),
                    AppColors.warmAlabaster,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.champagneGold : AppColors.borders,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.warmAlabaster
                        : AppColors.champagneGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? AppColors.champagneGold
                        : AppColors.refinedSlate,
                  ),
                ),
                const Spacer(),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? AppColors.champagneGold
                      : AppColors.refinedSlate.withValues(alpha: 0.30),
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.refinedSlate,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.refinedSlate.withValues(alpha: 0.65),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedType,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  Icons.spa_outlined,
                  color: AppColors.champagneGold.withValues(alpha: 0.82),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'Select procedure type',
                  style: TextStyle(
                    color: AppColors.refinedSlate.withValues(alpha: 0.46),
                  ),
                ),
              ],
            ),
          ),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          borderRadius: BorderRadius.circular(14),
          icon: Icon(
            Icons.expand_more_rounded,
            color: AppColors.refinedSlate.withValues(alpha: 0.62),
          ),
          selectedItemBuilder: (context) => _visibleProcedureTypes
              .map(
                (t) => Row(
                  children: [
                    Icon(
                      Icons.spa_outlined,
                      color: AppColors.champagneGold.withValues(alpha: 0.82),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.refinedSlate,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
          items: _visibleProcedureTypes
              .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
              .toList(),
          onChanged: (value) {
            setState(() {
              selectedType = value;
              _focusAreaUserEdited = false;
              selectedFocusArea = null;
              if (value != 'Other') {
                _customProcedureController.clear();
              }
              if (!_showsSessionField) {
                numSessions = 1;
              } else if (numSessions < 1) {
                numSessions = 1;
              }
              _refreshFocusAreaForProcedureChange();
            });
          },
        ),
      ),
    );
  }

  Widget _buildFocusAreaCard() {
    final options = _focusAreaOptions;
    final hasSelection = _hasFocusAreaSelection;
    final highlight = _requiresFocusArea;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _formCardDecoration(
        borderColor: highlight
            ? AppColors.champagneGold.withValues(alpha: 0.40)
            : null,
        shadowColor: highlight
            ? AppColors.champagneGold.withValues(alpha: 0.08)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: hasSelection
                      ? AppColors.mutedSage.withValues(alpha: 0.12)
                      : AppColors.champagneGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: hasSelection
                        ? AppColors.mutedSage.withValues(alpha: 0.26)
                        : AppColors.champagneGold.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  hasSelection
                      ? Icons.check_circle_rounded
                      : Icons.center_focus_strong_rounded,
                  size: 18,
                  color: hasSelection
                      ? AppColors.mutedSage
                      : AppColors.champagneGold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Required focus area',
                            style: TextStyle(
                              fontSize: 13.2,
                              fontWeight: FontWeight.w900,
                              color: AppColors.refinedSlate,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.champagneGold.withValues(
                                alpha: 0.34,
                              ),
                            ),
                          ),
                          child: const Text(
                            'REQUIRED',
                            style: TextStyle(
                              color: AppColors.champagneGold,
                              fontSize: 9.6,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasSelection
                          ? 'Scans and insights will track this exact area over time.'
                          : 'Choose the exact area scans should compare over time.',
                      style: TextStyle(
                        fontSize: 11.6,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: hasSelection
                            ? AppColors.mutedSage
                            : AppColors.refinedSlate.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in options)
                ChoiceChip(
                  label: Text(area),
                  selected: selectedFocusArea == area,
                  onSelected: (selected) {
                    setState(() {
                      _focusAreaUserEdited = true;
                      if (_requiresFocusArea && !selected) return;
                      selectedFocusArea = selected ? area : null;
                    });
                  },
                  selectedColor: AppColors.champagneGold.withValues(
                    alpha: 0.16,
                  ),
                  backgroundColor: AppColors.warmAlabaster,
                  side: BorderSide(
                    color: selectedFocusArea == area
                        ? AppColors.champagneGold
                        : AppColors.borders,
                    width: selectedFocusArea == area ? 1.2 : 0.8,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 11.8,
                    fontWeight: FontWeight.w800,
                    color: selectedFocusArea == area
                        ? AppColors.refinedSlate
                        : AppColors.refinedSlate.withValues(alpha: 0.72),
                  ),
                ),
            ],
          ),
          if (_isOtherFocusArea) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customDescriptionController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 140,
              decoration: _decoration(
                hint: _usesBodyFocusAreas
                    ? 'Describe the body area, e.g. hips or lower back'
                    : 'Describe the facial area or concern',
                icon: Icons.notes_rounded,
              ),
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration _formCardDecoration({Color? borderColor, Color? shadowColor}) {
    return BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: borderColor ?? AppColors.champagneGold.withValues(alpha: 0.20),
        width: borderColor == null ? 0.9 : 1.1,
      ),
      boxShadow: [
        BoxShadow(
          color: shadowColor ?? AppColors.refinedSlate.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  // ── Provider directory + manual entry ────────────────────────────────
  Future<void> _openProviderDirectory() async {
    final savedZip = await AppPrefs.getUserZipCode();
    if (!mounted) return;
    final currentProcedureType = _effectiveProcedureType();
    final result = await Navigator.of(context).push<Provider>(
      MaterialPageRoute(
        builder: (_) => ProviderDirectoryScreen(
          initialZip: savedZip.isEmpty ? null : savedZip,
          procedureType: currentProcedureType.isEmpty
              ? null
              : currentProcedureType,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _selectedProvider = result;
      _providerController.text = result.providerLabel;
      _manualEntryExpanded = false;
    });
  }

  void _clearSelectedProvider() {
    setState(() {
      _selectedProvider = null;
      _providerController.clear();
    });
  }

  Widget _buildProviderSection(Color textColor) {
    if (_selectedProvider != null) {
      return _buildSelectedProviderCard(_selectedProvider!, textColor);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary path: open directory
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openProviderDirectory,
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
            label: const Text('Find providers near me'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.champagneGold,
              backgroundColor: AppColors.cardBackground,
              side: const BorderSide(
                color: AppColors.champagneGold,
                width: 1.2,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Secondary path: manual entry (collapsed by default)
        if (!_manualEntryExpanded)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _manualEntryExpanded = true),
              icon: Icon(
                Icons.edit_outlined,
                size: 15,
                color: textColor.withValues(alpha: 0.75),
              ),
              label: Text(
                "Don't see your provider? Enter manually",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 32),
              ),
            ),
          )
        else ...[
          const SizedBox(height: 2),
          _buildProviderAutocomplete(),
          const SizedBox(height: 4),
          Text(
            'Start typing — we\'ll suggest popular clinics & providers.',
            style: TextStyle(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectedProviderCard(Provider p, Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.clinicName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.cityState,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: textColor.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: _clearSelectedProvider,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (p.boardCertified) ...[
                const Icon(
                  Icons.verified_rounded,
                  size: 14,
                  color: AppColors.mutedSage,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Board certified',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.mutedSage,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Icon(Icons.star_rounded, size: 14, color: MyApp.goldShimmer),
              const SizedBox(width: 2),
              Text(
                p.rating.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _openProviderDirectory,
                icon: const Icon(
                  Icons.swap_horiz_rounded,
                  size: 15,
                  color: AppColors.champagneGold,
                ),
                label: const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.champagneGold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderAutocomplete() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _providerController.text),
      optionsBuilder: (TextEditingValue value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<String>.empty();
        final starts = <String>[];
        final contains = <String>[];
        for (final c in _kKnownClinics) {
          final lower = c.toLowerCase();
          if (lower.startsWith(query)) {
            starts.add(c);
          } else if (lower.contains(query)) {
            contains.add(c);
          }
        }
        return [...starts, ...contains].take(6);
      },
      onSelected: (selection) {
        _providerController.text = selection;
        _providerController.selection = TextSelection.fromPosition(
          TextPosition(offset: selection.length),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        if (controller.text != _providerController.text) {
          controller.text = _providerController.text;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration(
            hint: 'e.g. Premier Aesthetics Clinic',
            icon: Icons.business_outlined,
          ),
          onChanged: (v) {
            _providerController.text = v;
            _providerController.selection = TextSelection.fromPosition(
              TextPosition(offset: v.length),
            );
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final option = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.business_outlined,
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.82,
                            ),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              option,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateTile() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (picked != null) setState(() => selectedDate = picked);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borders),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: AppColors.champagneGold.withValues(alpha: 0.82),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                DateFormat('MMM d, y').format(selectedDate),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.refinedSlate,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.refinedSlate.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Row(
        children: [
          _stepperButton(
            icon: Icons.remove_rounded,
            onTap: () =>
                setState(() => numSessions = (numSessions - 1).clamp(1, 50)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$numSessions',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.refinedSlate,
                  ),
                ),
                Text(
                  numSessions == 1 ? 'session' : 'sessions',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.refinedSlate.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _stepperButton(
            icon: Icons.add_rounded,
            onTap: () =>
                setState(() => numSessions = (numSessions + 1).clamp(1, 50)),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.champagneGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.28),
          ),
        ),
        child: Icon(icon, color: AppColors.champagneGold, size: 20),
      ),
    );
  }

  Widget _buildSaveButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: MyApp.buttonRadius,
        boxShadow: _isSubmitting
            ? null
            : [
                BoxShadow(
                  color: AppColors.champagneGold.withValues(alpha: 0.45),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _createProcedure,
        style: MyApp.primaryGoldButton,
        child: _isSubmitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                _isEditing ? 'Save changes' : 'Start Procedure',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}
