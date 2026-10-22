import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/procedure.dart' as models;
import '../models/procedure_log.dart';
import '../providers/procedure_logs_provider.dart';
import '../services/notification_service.dart';
import '../utils/premium_access.dart';
import '../utils/procedure_intelligence.dart';
import '../widgets/local_image_preview.dart';
import '../widgets/paywall_screen.dart';
import 'ai_recovery_coach_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';

class AtHomeProcedureLogScreen extends ConsumerStatefulWidget {
  const AtHomeProcedureLogScreen({super.key, this.existingLog});

  /// When set, the form opens pre-filled with this log and saving updates
  /// it in place (same id) instead of adding a new log.
  final ProcedureLog? existingLog;

  @override
  ConsumerState<AtHomeProcedureLogScreen> createState() =>
      _AtHomeProcedureLogScreenState();
}

class _AtHomeProcedureLogScreenState
    extends ConsumerState<AtHomeProcedureLogScreen> {
  static const String _medicalCategory = 'Medical';
  static const String _cosmeticCategory = 'Cosmetic';
  static const String _atHomeCategory = 'At-Home';

  static const List<String> _procedureCategories = [
    _medicalCategory,
    _cosmeticCategory,
    _atHomeCategory,
  ];

  static const Map<String, String> _procedureCategorySubtitles = {
    _medicalCategory: 'Resurfacing, collagen, lasers, injectables, surgery',
    _cosmeticCategory: 'Botox, fillers, professional peels, etc.',
    _atHomeCategory:
        'RF microneedling, SkinPen, chemical peels, red/blue/LED light therapy, GHK-Cu, dermaplaning, etc.',
  };

  static const List<String> _atHomeProcedureTypes = [
    'At-Home Microneedling (RF)',
    'At-Home Microneedling (SkinPen)',
    'At-Home Chemical Peel',
    'Red Light Therapy',
    'Blue Light Therapy',
    'LED Light Therapy',
    'GHK-Cu Serum Session',
    'At-Home Dermaplaning',
    'Custom Procedure',
  ];

  static const List<String> _medicalSuggestions = [
    'Halo Laser',
    'Clinical Microneedling',
    'BBL',
    'IPL Photofacial',
    'Morpheus8',
    'Clear + Brilliant',
    'CO2 Laser Resurfacing',
    'PRP Facial',
    'Surgical Procedure',
  ];

  static const List<String> _cosmeticSuggestions = [
    'Botox / Dysport / Xeomin',
    'Dermal Fillers',
    'Lip Augmentation',
    'TCA Peel',
    'Chemical Peel',
    'Hydrafacial',
    'Thread Lift',
    'Professional Facial',
  ];

  static const List<String> _expectedDurationOptions = [
    '1 month',
    '3 months',
    '4 months',
    '6 months',
    '9 months',
    '12 months',
    '18 months',
    'Other',
  ];

  static const List<String> _commonProducts = [
    'GHK-Cu',
    'Hyaluronic Acid',
    'Peptide Serum',
    'Growth Factors',
    'Barrier Cream',
    'Hypochlorous Spray',
    'SPF',
  ];

  final _formKey = GlobalKey<FormState>();
  final _customProcedureController = TextEditingController();
  final _professionalProcedureController = TextEditingController();
  final _clinicNameController = TextEditingController();
  final _providerNameController = TextEditingController();
  final _costController = TextEditingController();
  final _settingsController = TextEditingController();
  final _notesController = TextEditingController();
  final _productController = TextEditingController();
  final _customDurationController = TextEditingController();
  final _imagePicker = ImagePicker();

  String _selectedCategory = _atHomeCategory;
  String _selectedProcedureType = _atHomeProcedureTypes.first;
  DateTime _dateTime = DateTime.now();
  final List<_ProcedurePhoto> _photos = [];
  final Set<String> _selectedProducts = {'GHK-Cu'};
  double _intensity = 3;
  double _reactionScore = 3;
  bool _saving = false;
  String? _selectedExpectedDuration;
  bool _reminderEnabled = true;

  bool get _isEditing => widget.existingLog != null;

  @override
  void initState() {
    super.initState();
    _reminderEnabled = true;
    final log = widget.existingLog;
    if (log != null) _prefillFrom(log);
  }

  /// The value after "[key]:" on its own line in a log's combined
  /// settings (see [_combinedSettings]), or null.
  static String? _settingsValue(String? settings, String key) {
    if (settings == null) return null;
    final prefix = '${key.toLowerCase()}:';
    for (final line in settings.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith(prefix)) {
        final value = trimmed.substring(prefix.length).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  /// Fills the form from [log] so it can be edited.
  void _prefillFrom(ProcedureLog log) {
    final category =
        log.category ?? _settingsValue(log.settings, 'Category');
    _selectedCategory = _procedureCategories.contains(category)
        ? category!
        : _atHomeCategory;
    if (_usesProfessionalFields) {
      _professionalProcedureController.text = log.procedureType;
      _clinicNameController.text = _settingsValue(log.settings, 'Clinic') ?? '';
      _providerNameController.text =
          _settingsValue(log.settings, 'Provider') ?? '';
      _costController.text = _settingsValue(log.settings, 'Cost') ?? '';
      final duration = log.expectedDuration;
      if (duration != null && duration.isNotEmpty) {
        if (_expectedDurationOptions.contains(duration)) {
          _selectedExpectedDuration = duration;
        } else {
          _selectedExpectedDuration = 'Other';
          _customDurationController.text = duration;
        }
      }
      _reminderEnabled = log.reminderEnabled;
    } else if (_atHomeProcedureTypes.contains(log.procedureType)) {
      _selectedProcedureType = log.procedureType;
    } else {
      _selectedProcedureType = 'Custom Procedure';
      _customProcedureController.text = log.procedureType;
    }
    _settingsController.text = _settingsValue(log.settings, 'Settings') ?? '';
    _notesController.text = log.notes ?? '';
    _dateTime = log.dateTime;
    _intensity = (log.intensity ?? _intensity).clamp(0, 10).toDouble();
    _reactionScore = (log.reactionScore ?? _reactionScore)
        .clamp(1, 10)
        .toDouble();
    _selectedProducts
      ..clear()
      ..addAll(log.productsUsed);
    _photos
      ..clear()
      ..addAll([
        for (final photo in log.labeledPhotos)
          _ProcedurePhoto(label: photo.label, path: photo.path),
      ]);
  }

  @override
  void dispose() {
    _customProcedureController.dispose();
    _professionalProcedureController.dispose();
    _clinicNameController.dispose();
    _providerNameController.dispose();
    _costController.dispose();
    _settingsController.dispose();
    _notesController.dispose();
    _productController.dispose();
    _customDurationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logsState = ref.watch(procedureLogsProvider);
    final providerSaving = logsState.isLoading;
    final canSave = !_saving && !providerSaving;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Procedure Log' : 'Track Procedure'),
        actions: [
          TextButton.icon(
            onPressed: canSave ? _saveLog : null,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            _categorySection(),
            const SizedBox(height: 14),
            _HeaderCard(photoCount: _photos.length),
            const SizedBox(height: 16),
            _FormSection(
              title: 'Procedure',
              icon: Icons.auto_awesome_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isAtHome) _atHomeProcedureFields(),
                  if (_usesProfessionalFields) _professionalProcedureFields(),
                  const SizedBox(height: 12),
                  _DateTimeTile(dateTime: _dateTime, onTap: _pickDateTime),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_usesProfessionalFields) ...[
              _professionalDetailsSection(),
              const SizedBox(height: 14),
            ],
            _FormSection(
              title: 'Photos',
              icon: Icons.photo_camera_back_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        const [
                              _PhotoAddButton(label: 'Before'),
                              _PhotoAddButton(label: 'After'),
                              _PhotoAddButton(label: 'Progress'),
                            ]
                            .map(
                              (button) => _PhotoAddButton(
                                label: button.label,
                                onTap: () =>
                                    _showPhotoSourceSheet(button.label),
                              ),
                            )
                            .toList(),
                  ),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 112,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final photo = _photos[index];
                          return _PhotoPreviewTile(
                            photo: photo,
                            onRemove: () =>
                                setState(() => _photos.removeAt(index)),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _FormSection(
              title: _isAtHome
                  ? 'At-Home Intensity & Settings'
                  : '$_selectedCategory Treatment Details',
              icon: Icons.tune_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isAtHome) ...[
                    const _GoldNote(
                      text:
                          'Track device depth, passes, or energy clearly so your results are easier to compare next time.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  _SliderField(
                    label: 'Intensity',
                    valueLabel: '${_intensity.round()}/10',
                    value: _intensity,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    onChanged: (value) => setState(() => _intensity = value),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _settingsController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Settings',
                      hintText: '1.5mm, 2 passes, level 3, 10 minutes',
                      prefixIcon: Icon(Icons.straighten_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _FormSection(
              title: 'Products Used',
              icon: Icons.science_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._commonProducts,
                      ..._selectedProducts.where(
                        (p) => !_commonProducts.contains(p),
                      ),
                    ].map(_buildProductChip).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _productController,
                          decoration: const InputDecoration(
                            labelText: 'Add product',
                            prefixIcon: Icon(Icons.add_circle_outline),
                          ),
                          onFieldSubmitted: (_) => _addCustomProduct(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: _addCustomProduct,
                        icon: const Icon(Icons.add_rounded),
                        tooltip: 'Add product',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _FormSection(
              title: 'Reaction & Notes',
              icon: Icons.favorite_border_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SliderField(
                    label: 'Reaction score',
                    valueLabel:
                        '${_reactionEmoji(_reactionScore.round())} ${_reactionScore.round()}/10',
                    value: _reactionScore,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    activeColor: _reactionColor(_reactionScore.round()),
                    onChanged: (value) =>
                        setState(() => _reactionScore = value),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notesController,
                    minLines: 4,
                    maxLines: 7,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      hintText:
                          'Skin response, technique, downtime, comfort...',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: canSave ? _saveLog : null,
              style: MyApp.primaryGoldButton,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isEditing ? 'Save Changes' : 'Save Procedure Log'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categorySection() {
    return _FormSection(
      title: 'Procedure Category',
      icon: Icons.category_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: _procedureCategories.map((category) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: category == _procedureCategories.last ? 0 : 8,
                  ),
                  child: _CategorySelectorButton(
                    title: category,
                    selected: _selectedCategory == category,
                    isDefault: category == _atHomeCategory,
                    onTap: () => setState(() {
                      _selectedCategory = category;
                      _selectedExpectedDuration = null;
                      _customDurationController.clear();
                      _reminderEnabled = true;
                      _professionalProcedureController.clear();
                    }),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          _CategorySummary(
            title: _selectedCategory,
            subtitle: _procedureCategorySubtitles[_selectedCategory] ?? '',
            isDefault: _isAtHome,
          ),
        ],
      ),
    );
  }

  Widget _atHomeProcedureFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedProcedureType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Procedure type',
            prefixIcon: Icon(Icons.spa_outlined),
          ),
          items: _atHomeProcedureTypes
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(type, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedProcedureType = value);
          },
        ),
        if (_usesCustomProcedure) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _customProcedureController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Custom procedure name',
              prefixIcon: Icon(Icons.edit_note_outlined),
            ),
            validator: (value) {
              if (!_usesCustomProcedure) return null;
              if (value == null || value.trim().isEmpty) {
                return 'Enter a procedure name.';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _professionalProcedureFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _professionalProcedureController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _onProcedureTypeChanged(),
          decoration: InputDecoration(
            labelText: '$_selectedCategory procedure type',
            hintText: _professionalProcedureHint,
            prefixIcon: const Icon(Icons.local_hospital_outlined),
          ),
          validator: (value) {
            if (!_usesProfessionalFields) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Enter the ${_selectedCategory.toLowerCase()} procedure type.';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _professionalSuggestions.map((suggestion) {
            return ActionChip(
              label: Text(suggestion),
              avatar: const Icon(Icons.add_rounded, size: 16),
              side: BorderSide(
                color: AppColors.champagneGold.withValues(alpha: 0.35),
              ),
              onPressed: () {
                setState(() {
                  _professionalProcedureController.text = suggestion;
                  _onProcedureTypeChanged();
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _professionalDetailsSection() {
    return _FormSection(
      title: '$_selectedCategory Provider Details',
      icon: Icons.apartment_outlined,
      child: Column(
        children: [
          TextFormField(
            controller: _clinicNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Clinic name',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _providerNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Provider name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _costController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Cost optional',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _selectedExpectedDuration,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Expected duration',
              prefixIcon: Icon(Icons.schedule_outlined),
            ),
            items: _expectedDurationOptions.map((duration) {
              return DropdownMenuItem(value: duration, child: Text(duration));
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedExpectedDuration = value;
                if (value != 'Other') {
                  _customDurationController.clear();
                }
              });
            },
          ),
          if (_selectedExpectedDuration == 'Other') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _customDurationController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Custom duration',
                hintText: 'e.g., 2 months, 5 months',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Enable reminder for next treatment',
                  style: TextStyle(color: MyApp.clinicalSlate),
                ),
              ),
              Switch(
                value: _reminderEnabled,
                onChanged: (value) => setState(() => _reminderEnabled = value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _isAtHome => _selectedCategory == _atHomeCategory;

  bool get _isMedical => _selectedCategory == _medicalCategory;

  bool get _isCosmetic => _selectedCategory == _cosmeticCategory;

  bool get _usesProfessionalFields => _isMedical || _isCosmetic;

  bool get _usesCustomProcedure => _selectedProcedureType == 'Custom Procedure';

  List<String> get _professionalSuggestions =>
      _isMedical ? _medicalSuggestions : _cosmeticSuggestions;

  String get _professionalProcedureHint => _isMedical
      ? 'Halo Laser, clinical microneedling, surgery...'
      : 'Botox, fillers, professional peel...';

  String get _procedureName {
    if (_usesProfessionalFields) {
      return _professionalProcedureController.text.trim();
    }
    if (_usesCustomProcedure) return _customProcedureController.text.trim();
    return _selectedProcedureType;
  }

  String? get _combinedSettings {
    final parts = <String>['Category: $_selectedCategory'];
    final settings = _settingsController.text.trim();
    final clinic = _clinicNameController.text.trim();
    final provider = _providerNameController.text.trim();
    final cost = _costController.text.trim();

    if (_usesProfessionalFields) {
      if (clinic.isNotEmpty) parts.add('Clinic: $clinic');
      if (provider.isNotEmpty) parts.add('Provider: $provider');
      if (cost.isNotEmpty) parts.add('Cost: $cost');
    }
    if (settings.isNotEmpty) parts.add('Settings: $settings');

    return parts.isEmpty ? null : parts.join('\n');
  }

  DateTime? _calculateNextReminderDate() {
    // Pre-fill durations for common injectables
    final procedureLower = _procedureName.toLowerCase();
    int monthsToAdd = 6; // Default

    if (procedureLower.contains('botox') ||
        procedureLower.contains('dysport') ||
        procedureLower.contains('xeomin')) {
      monthsToAdd = 3;
    } else if (procedureLower.contains('filler')) {
      monthsToAdd = 6;
    } else if (_selectedExpectedDuration != null &&
        _selectedExpectedDuration != 'Other') {
      // Parse standard duration
      final match = RegExp(r'(\d+)').firstMatch(_selectedExpectedDuration!);
      if (match != null) {
        monthsToAdd = int.parse(match.group(1)!);
      }
    }

    return _dateTime.add(Duration(days: monthsToAdd * 30)); // Approximate
  }

  void _onProcedureTypeChanged() {
    // Auto-fill duration for professional categories
    if (_usesProfessionalFields) {
      final procedureLower = _procedureName.toLowerCase();
      if (procedureLower.contains('botox') ||
          procedureLower.contains('dysport') ||
          procedureLower.contains('xeomin')) {
        setState(() => _selectedExpectedDuration = '3 months');
      } else if (procedureLower.contains('filler')) {
        setState(() => _selectedExpectedDuration = '6 months');
      }
    }
  }

  Widget _buildProductChip(String product) {
    final selected = _selectedProducts.contains(product);
    return FilterChip(
      selected: selected,
      label: Text(product),
      selectedColor: AppColors.champagneGold.withValues(alpha: 0.22),
      checkmarkColor: AppColors.champagneGold,
      side: BorderSide(
        color: selected
            ? AppColors.champagneGold
            : AppColors.borders.withValues(alpha: 0.9),
      ),
      onSelected: (value) {
        setState(() {
          if (value) {
            _selectedProducts.add(product);
          } else {
            _selectedProducts.remove(product);
          }
        });
      },
    );
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _dateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  void _addCustomProduct() {
    final product = _productController.text.trim();
    if (product.isEmpty) return;
    setState(() {
      _selectedProducts.add(product);
      _productController.clear();
    });
  }

  void _showPhotoSourceSheet(String label) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MyApp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borders,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_outlined,
                    color: AppColors.champagneGold,
                  ),
                  title: Text('Take $label Photo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickPhoto(label: label, source: ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.champagneGold,
                  ),
                  title: Text(
                    kIsWeb ? 'Upload $label Photo' : 'Choose $label Photo',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickPhoto(label: label, source: ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickPhoto({
    required String label,
    required ImageSource source,
  }) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (file == null || !mounted) return;

      setState(() {
        _photos.add(_ProcedurePhoto(label: label, path: file.path));
      });
      _showSnackBar('$label photo added.');
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showSnackBar(
        'Could not open photo source: ${error.message ?? error.code}',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Could not add photo: $error');
    }
  }

  Future<void> _saveLog() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    // Calculate nextReminderDate if reminder is enabled
    DateTime? nextReminderDate;
    if (_reminderEnabled && _usesProfessionalFields) {
      nextReminderDate = _calculateNextReminderDate();
    }

    // Get expected duration value
    String? expectedDuration = _selectedExpectedDuration;
    if (expectedDuration == 'Other' &&
        _customDurationController.text.trim().isNotEmpty) {
      expectedDuration = _customDurationController.text.trim();
    }

    final existing = widget.existingLog;
    final log = ProcedureLog(
      id: existing?.id,
      createdAt: existing?.createdAt,
      aiFeedback: existing?.aiFeedback,
      photoCalibrationByPath: existing?.photoCalibrationByPath ?? const {},
      procedureType: _procedureName,
      dateTime: _dateTime,
      notes: _emptyToNull(_notesController.text),
      photoPaths: _photos.map((photo) => photo.path).toList(),
      photoLabels: _photos.map((photo) => photo.label).toList(),
      intensity: _intensity.round(),
      settings: _combinedSettings,
      productsUsed: _selectedProducts.toList()..sort(),
      reactionScore: _reactionScore.round(),
      category: _usesProfessionalFields ? _selectedCategory : null,
      expectedDuration: _usesProfessionalFields ? expectedDuration : null,
      nextReminderDate: nextReminderDate,
      reminderEnabled: _reminderEnabled && _usesProfessionalFields,
    );

    if (existing != null) {
      await _saveEditedLog(log);
      return;
    }

    // ── Freemium gate: free tier capped at 8 procedure logs ──────────────
    try {
      final currentLogs = ref.read(procedureLogsProvider).valueOrNull ?? [];
      const int freeLogLimit = 8;
      if (currentLogs.length >= freeLogLimit) {
        final isPremium = await PremiumAccess.isPremiumUser();
        if (!isPremium) {
          if (!mounted) return;
          setState(() => _saving = false);
          _showFreemiumLimitDialog();
          return;
        }
      }
    } catch (_) {
      // Gate check failure is non-fatal — allow save to proceed.
    }
    // ─────────────────────────────────────────────────────────────────────

    try {
      await ref.read(procedureLogsProvider.notifier).addLog(log);

      // Debug: Confirm photo persistence and that photos are linked to THIS log
      debugPrint(
        'Saved ProcedureLog ${log.id} with '
        '${log.photoPaths.length} photos: ${log.photoPaths}',
      );

      // Force provider refresh so UI updates immediately
      ref.invalidate(procedureLogsProvider);
      await ref.read(procedureLogsProvider.future);

      // Schedule notification reminder if enabled (skip on web)
      if (!kIsWeb && log.reminderEnabled && log.nextReminderDate != null) {
        try {
          await NotificationService().scheduleReminderForProcedure(log);
        } catch (_) {
          // Notification scheduling is optional; continue even if it fails
        }
      }

      if (!mounted) return;
      setState(() => _saving = false);
      _showSavedSheet(log);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnackBar('Could not save procedure log: $error');
    }
  }

  /// Saves an edited log over the existing entry (same id) and replaces its
  /// reminder: the old one is cancelled and, if still enabled, rescheduled
  /// for the new date. Not counted against the free log limit.
  Future<void> _saveEditedLog(ProcedureLog log) async {
    try {
      await ref.read(procedureLogsProvider.notifier).updateLog(log);
      if (!kIsWeb) {
        try {
          final notifications = NotificationService();
          await notifications.cancelReminder(log.id);
          if (log.reminderEnabled && log.nextReminderDate != null) {
            await notifications.scheduleReminderForProcedure(log);
          }
        } catch (_) {
          // Reminders are optional; the edit is already saved.
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(log);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnackBar('Could not save changes: $error');
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showFreemiumLimitDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: MyApp.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Icon + headline
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: MyApp.roseGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 32,
                color: MyApp.roseGold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "You've Reached the Free Limit",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Free accounts can log up to 8 procedures. Upgrade to Premium to track unlimited procedures and unlock the full experience.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.55,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 20),
            // Benefits list
            const _FreemiumBenefit(
              icon: Icons.all_inclusive_rounded,
              text: 'Unlimited procedure logs',
            ),
            const SizedBox(height: 8),
            const _FreemiumBenefit(
              icon: Icons.auto_awesome_rounded,
              text: 'Full Gemini Vision AI analysis',
            ),
            const SizedBox(height: 8),
            const _FreemiumBenefit(
              icon: Icons.trending_up_rounded,
              text: 'Advanced AI trend insights',
            ),
            const SizedBox(height: 8),
            const _FreemiumBenefit(
              icon: Icons.download_rounded,
              text: 'Export procedure reports (PDF)',
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PaywallScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.star_rounded, size: 20),
              label: const Text('Upgrade to Premium'),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.roseGold,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.black45),
              child: const Text('Maybe Later'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSavedSheet(ProcedureLog log) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MyApp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.champagneGold.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.champagneGold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Procedure saved',
                        style: MyApp.sectionTitleStyle(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${log.procedureType} is now in your procedure tracker.',
                  style: TextStyle(color: MyApp.clinicalSlate, height: 1.4),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openCoachForLog(log);
                  },
                  style: MyApp.primaryGoldButton,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(_logFollowUpActionLabel(log)),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.pop(context, log);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _logFollowUpActionLabel(ProcedureLog log) {
    final category = ProcedureIntelligence.categoryFor(log.procedureType);
    final isRecoveryProcedure =
        category == ProcedureCategory.bodyContouring ||
        category == ProcedureCategory.surgicalFace ||
        category == ProcedureCategory.hairTransplant;
    return isRecoveryProcedure ? 'Open Recovery Coach' : 'Open Skin Scan';
  }

  /// Routes skincare-oriented logs into the unified Skin Scan flow and keeps
  /// recovery-specific procedures on the existing recovery coach surface.
  /// procedure. Surgical / body-contouring / hair-transplant procedures (e.g.
  /// liposuction, BBL, facelift) belong to the Recovery Coach, which is built
  /// for procedure recovery and aftercare. Skincare / laser / injectable
  /// procedures now go to the combined Skin Scan flow.
  void _openCoachForLog(ProcedureLog log) {
    final category = ProcedureIntelligence.categoryFor(log.procedureType);
    final isRecoveryProcedure =
        category == ProcedureCategory.bodyContouring ||
        category == ProcedureCategory.surgicalFace ||
        category == ProcedureCategory.hairTransplant;

    if (isRecoveryProcedure) {
      final procedure = models.Procedure(
        id: log.id,
        type: log.procedureType,
        provider: 'Professional',
        startDate: log.dateTime,
        numSessions: 1,
        notes: log.notes ?? '',
        taggedPhotos: log.photoPaths,
      );
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AIRecoveryCoachScreen(procedure: procedure),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const SkinAiAnalysisScreen(),
      ),
    );
  }

  String _reactionEmoji(int score) {
    if (score <= 2) return '😊';
    if (score <= 5) return '🙂';
    if (score <= 7) return '😐';
    return '🔥';
  }

  Color _reactionColor(int score) {
    if (score <= 3) return AppColors.mutedSage;
    if (score <= 7) return AppColors.champagneGold;
    return AppColors.softTerracotta;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.photoCount});

  final int photoCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.12),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.champagneGold,
                  AppColors.champagneGold.withValues(alpha: 0.65),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.champagneGold.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.spa_outlined,
              color: AppColors.onChampagneGold,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Procedure tracker', style: MyApp.cardTitleStyle()),
                const SizedBox(height: 4),
                Text(
                  photoCount == 0
                      ? 'Track at-home, cosmetic, and medical procedures with settings, photos, products, and skin response in one polished record.'
                      : '$photoCount photo${photoCount == 1 ? '' : 's'} attached to this log.',
                  style: TextStyle(color: MyApp.clinicalSlate, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: MyApp.cardPadding,
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.champagneGold, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: MyApp.cardTitleStyle())),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CategorySelectorButton extends StatelessWidget {
  const _CategorySelectorButton({
    required this.title,
    required this.selected,
    required this.onTap,
    this.isDefault = false,
  });

  final String title;
  final bool selected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.champagneGold.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.champagneGold.withValues(alpha: 0.64)
                : AppColors.borders.withValues(alpha: 0.9),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.champagneGold : MyApp.clinicalMuted,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? MyApp.textBrown : MyApp.clinicalSlate,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (isDefault) ...[
              const SizedBox(height: 5),
              const _DefaultCategoryPill(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategorySummary extends StatelessWidget {
  const _CategorySummary({
    required this.title,
    required this.subtitle,
    this.isDefault = false,
  });

  final String title;
  final String subtitle;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.champagneGold,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: MyApp.cardTitleStyle())),
                    if (isDefault) const _DefaultCategoryPill(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: MyApp.clinicalSlate,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultCategoryPill extends StatelessWidget {
  const _DefaultCategoryPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.35),
        ),
      ),
      child: const Text(
        'Default',
        style: TextStyle(
          color: AppColors.champagneGold,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GoldNote extends StatelessWidget {
  const _GoldNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.tips_and_updates_outlined,
            color: AppColors.champagneGold,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: MyApp.clinicalSlate,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({required this.dateTime, required this.onTap});

  final DateTime dateTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: MyApp.isDark ? 0.06 : 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borders.withValues(alpha: 0.9)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.event_available_outlined,
              color: AppColors.champagneGold,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date & time',
                    style: TextStyle(color: MyApp.clinicalMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('MMM d, yyyy • h:mm a').format(dateTime),
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _PhotoAddButton extends StatelessWidget {
  const _PhotoAddButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add_photo_alternate_outlined),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: MyApp.textBrown,
        side: BorderSide(
          color: AppColors.champagneGold.withValues(alpha: 0.48),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _PhotoPreviewTile extends StatelessWidget {
  const _PhotoPreviewTile({required this.photo, required this.onRemove});

  final _ProcedurePhoto photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.champagneGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.24),
                ),
              ),
              child: buildLocalImagePreview(
                photo.path,
                width: 104,
                height: 112,
                borderRadius: 16,
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.52),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                photo.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.activeColor,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: MyApp.textBrown,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: activeColor ?? AppColors.champagneGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: activeColor ?? AppColors.champagneGold,
            thumbColor: activeColor ?? AppColors.champagneGold,
            overlayColor: (activeColor ?? AppColors.champagneGold).withValues(
              alpha: 0.16,
            ),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Small benefit row used inside _showFreemiumLimitDialog.
class _FreemiumBenefit extends StatelessWidget {
  const _FreemiumBenefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MyApp.roseGold),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _ProcedurePhoto {
  const _ProcedurePhoto({required this.label, required this.path});

  final String label;
  final String path;
}
