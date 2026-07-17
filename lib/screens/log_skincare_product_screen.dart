// lib/screens/log_skincare_product_screen.dart
// Redesigned: single "Product" field, optional Brand with smart auto-detect,
// optional photo upload with preview, cleaner spacing & visual hierarchy.

import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
// ignore: unused_import
import '../widgets/clinical_section_header.dart';
import '../models/product_tracker.dart';
import '../utils/app_prefs.dart';

/// Common skincare brand list used for auto-detect from the Product field
/// and for autocomplete suggestions in the Brand field.
const List<String> _kKnownBrands = <String>[
  'The Ordinary',
  'CeraVe',
  'La Roche-Posay',
  'Cetaphil',
  'Neutrogena',
  'Olay',
  'Skinceuticals',
  "Paula's Choice",
  'Drunk Elephant',
  "Kiehl's",
  'Tatcha',
  'Sunday Riley',
  'Glow Recipe',
  'COSRX',
  'Beauty of Joseon',
  'Some By Mi',
  'Innisfree',
  'Laneige',
  'Klairs',
  'Estée Lauder',
  'Clinique',
  'Origins',
  'Murad',
  'Kate Somerville',
  'IT Cosmetics',
  'Fresh',
  'Ole Henriksen',
  'First Aid Beauty',
  'Youth To The People',
  'Pyunkang Yul',
  'Mizon',
  'Bioderma',
  'Avene',
  'Vichy',
  'Eucerin',
  'Aveeno',
  'Differin',
  'Obagi',
  'Skinmedica',
  'Alastin',
  'Revision Skincare',
  'iS Clinical',
  'EltaMD',
  'Supergoop',
];

/// Curated list of popular skincare products (Western + K-beauty).
/// Each entry is the full marketed name; brand auto-fills via prefix match
/// against [_kKnownBrands] when selected.
const List<String> _kKnownProducts = <String>[
  // Korean / K-beauty
  'COSRX Advanced Snail 96 Mucin Power Essence',
  'COSRX BHA Blackhead Power Liquid',
  'COSRX AHA/BHA Clarifying Treatment Toner',
  'COSRX Centella Blemish Cream',
  'COSRX Acne Pimple Master Patch',
  'Beauty of Joseon Relief Sun: Rice + Probiotics SPF 50+',
  'Beauty of Joseon Glow Serum: Propolis + Niacinamide',
  'Beauty of Joseon Dynasty Cream',
  'Beauty of Joseon Revive Eye Serum: Ginseng + Retinal',
  'Some By Mi AHA-BHA-PHA 30 Days Miracle Toner',
  'Some By Mi Snail Truecica Miracle Repair Serum',
  'Innisfree Green Tea Seed Hyaluronic Serum',
  'Innisfree Volcanic Pore Clay Mask',
  'Laneige Water Sleeping Mask',
  'Laneige Lip Sleeping Mask',
  'Klairs Freshly Juiced Vitamin Drop',
  'Klairs Supple Preparation Unscented Toner',
  'Klairs Midnight Blue Calming Cream',
  'Pyunkang Yul Essence Toner',
  'Pyunkang Yul Moisture Cream',
  'Mizon Snail Repair Intensive Ampoule',
  'Mizon All In One Snail Repair Cream',
  'Tatcha The Dewy Skin Cream',
  'Tatcha The Water Cream',
  'Glow Recipe Watermelon Glow Niacinamide Dew Drops',
  'Glow Recipe Plum Plump Hyaluronic Serum',
  'Glow Recipe Avocado Melt Retinol Sleeping Mask',

  // The Ordinary
  'The Ordinary Niacinamide 10% + Zinc 1%',
  'The Ordinary Hyaluronic Acid 2% + B5',
  'The Ordinary Granactive Retinoid 2% Emulsion',
  'The Ordinary Retinol 0.5% in Squalane',
  'The Ordinary AHA 30% + BHA 2% Peeling Solution',
  'The Ordinary Glycolic Acid 7% Exfoliating Toner',
  'The Ordinary Salicylic Acid 2% Solution',
  'The Ordinary Buffet',
  'The Ordinary Caffeine Solution 5% + EGCG',
  'The Ordinary Squalane Cleanser',
  'The Ordinary Natural Moisturizing Factors + HA',

  // CeraVe
  'CeraVe Moisturizing Cream',
  'CeraVe Daily Moisturizing Lotion',
  'CeraVe Hydrating Facial Cleanser',
  'CeraVe Foaming Facial Cleanser',
  'CeraVe SA Smoothing Cleanser',
  'CeraVe AM Facial Moisturizing Lotion SPF 30',
  'CeraVe PM Facial Moisturizing Lotion',
  'CeraVe Resurfacing Retinol Serum',
  'CeraVe Hydrating Hyaluronic Acid Serum',

  // La Roche-Posay
  'La Roche-Posay Toleriane Double Repair Face Moisturizer',
  'La Roche-Posay Toleriane Hydrating Gentle Cleanser',
  'La Roche-Posay Effaclar Duo',
  'La Roche-Posay Effaclar Medicated Gel Cleanser',
  'La Roche-Posay Anthelios Melt-in Milk Sunscreen SPF 60',
  'La Roche-Posay Anthelios UV Correct SPF 70',
  'La Roche-Posay Cicaplast Baume B5',

  // Drunk Elephant
  'Drunk Elephant Protini Polypeptide Cream',
  'Drunk Elephant C-Firma Fresh Day Serum',
  'Drunk Elephant T.L.C. Sukari Babyfacial',
  'Drunk Elephant Lala Retro Whipped Cream',
  'Drunk Elephant B-Hydra Intensive Hydration Serum',

  // Paula's Choice
  "Paula's Choice 2% BHA Liquid Exfoliant",
  "Paula's Choice 8% AHA Gel Exfoliant",
  "Paula's Choice 10% Niacinamide Booster",
  "Paula's Choice C15 Super Booster",
  "Paula's Choice Resist Anti-Aging Moisturizer",

  // Skinceuticals
  'SkinCeuticals C E Ferulic',
  'SkinCeuticals Phloretin CF',
  'SkinCeuticals Hydrating B5 Gel',
  'SkinCeuticals Triple Lipid Restore 2:4:2',

  // Sunscreens & misc favorites
  'EltaMD UV Clear Broad-Spectrum SPF 46',
  'EltaMD UV Daily Tinted SPF 40',
  'Supergoop! Unseen Sunscreen SPF 40',
  'Supergoop! Glowscreen SPF 40',
  'Neutrogena Hydro Boost Water Gel',
  'Neutrogena Ultra Sheer Dry-Touch Sunscreen SPF 55',
  'Cetaphil Gentle Skin Cleanser',
  'Cetaphil Daily Facial Moisturizer SPF 15',
  'Olay Regenerist Micro-Sculpting Cream',
  'Aveeno Calm + Restore Oat Gel Moisturizer',
  'First Aid Beauty Ultra Repair Cream',
  'Youth To The People Superfood Cleanser',
  'Youth To The People Superberry Hydrate + Glow Dream Mask',
  'Fresh Soy Face Cleanser',
  'Fresh Rose Deep Hydration Face Cream',
  "Kiehl's Ultra Facial Cream",
  "Kiehl's Midnight Recovery Concentrate",
  'Sunday Riley Good Genes All-In-One Lactic Acid Treatment',
  'Sunday Riley A+ High-Dose Retinoid Serum',
  'Murad Vitamin C Glycolic Brightening Serum',
  'Differin Adapalene Gel 0.1% Acne Treatment',
  'Bioderma Sensibio H2O Micellar Water',
  'Avene Thermal Spring Water',
  'Vichy Mineral 89 Hyaluronic Acid Serum',
  'Eucerin Advanced Repair Cream',
];

class LogSkincareProductScreen extends StatefulWidget {
  final TrackedProduct? existingProduct;

  const LogSkincareProductScreen({super.key, this.existingProduct});

  const LogSkincareProductScreen.edit({
    super.key,
    required TrackedProduct product,
  }) : existingProduct = product;

  @override
  State<LogSkincareProductScreen> createState() =>
      _LogSkincareProductScreenState();
}

class _LogSkincareProductScreenState extends State<LogSkincareProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _ingredientsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  DateTime _startDate = DateTime.now();
  int _rating = 0;
  bool _isSaving = false;
  String? _photoPath;
  bool _userEditedBrand = false;

  bool get _isEditing => widget.existingProduct != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProduct;
    if (existing != null) {
      _nameController.text = existing.name;
      _brandController.text = existing.brand;
      _ingredientsController.text = existing.keyIngredients;
      _notesController.text = existing.notes;
      _startDate = existing.startDate;
      _rating = existing.rating;
      _photoPath = existing.photoPath;
      _userEditedBrand = existing.brand.trim().isNotEmpty;
    }
    _nameController.addListener(_maybeAutoFillBrand);
  }

  @override
  void dispose() {
    _nameController.removeListener(_maybeAutoFillBrand);
    _nameController.dispose();
    _brandController.dispose();
    _ingredientsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _maybeAutoFillBrand() {
    if (_userEditedBrand) return;
    final text = _nameController.text.trim();
    if (text.isEmpty) return;
    final lower = text.toLowerCase();
    for (final brand in _kKnownBrands) {
      if (lower.startsWith(brand.toLowerCase())) {
        if (_brandController.text != brand) {
          _brandController.text = brand;
        }
        return;
      }
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _pickPhoto({required ImageSource source}) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() => _photoPath = file.path);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open photo source: ${e.message ?? e.code}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not pick photo: $e')));
      }
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_outlined,
                    color: AppColors.champagneGold,
                  ),
                  title: const Text(
                    'Take Photo',
                    style: TextStyle(color: AppColors.refinedSlate),
                  ),
                  subtitle: const Text('Use your camera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPhoto(source: ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.champagneGold,
                  ),
                  title: const Text(
                    kIsWeb ? 'Upload from device' : 'Choose from Gallery',
                  ),
                  subtitle: const Text(
                    kIsWeb
                        ? 'Pick an image file from your computer'
                        : 'Select a photo from your library',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPhoto(source: ImageSource.gallery);
                  },
                ),
                if (_photoPath != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: AppColors.softTerracotta,
                    ),
                    title: const Text('Remove photo'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _photoPath = null);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final product = TrackedProduct(
      id:
          widget.existingProduct?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      brand: _brandController.text.trim(),
      keyIngredients: _ingredientsController.text.trim(),
      notes: _notesController.text.trim(),
      startDate: _startDate,
      endDate: widget.existingProduct?.endDate,
      rating: _rating,
      photoPath: _photoPath,
    );

    try {
      if (_isEditing) {
        await AppPrefs.updateTrackedProduct(product);
      } else {
        await AppPrefs.addTrackedProduct(product);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Product updated' : 'Product saved'),
          ),
        );
        Navigator.pop(context, product);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving product: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const ClinicalAppBarTitle(
          title: 'Log Skincare',
          eyebrow: 'Routine entry',
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.refinedSlate,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 22),

              // ===== Product (main field) =====
              _fieldLabel('Product', required: true),
              const SizedBox(height: 6),
              _buildProductAutocomplete(),
              const SizedBox(height: 6),
              Text(
                'Start typing — we\'ll suggest popular products and auto-detect the brand.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.refinedSlate.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 18),

              // ===== Brand (optional, autocomplete) =====
              _fieldLabel('Brand', optional: true),
              const SizedBox(height: 6),
              _buildBrandAutocomplete(),

              const SizedBox(height: 18),

              // ===== Photo (optional) =====
              _fieldLabel('Photo', optional: true),
              const SizedBox(height: 6),
              _buildPhotoPicker(),

              const SizedBox(height: 18),

              // ===== Key ingredients =====
              _fieldLabel('Key Ingredients', optional: true),
              const SizedBox(height: 6),
              TextFormField(
                controller: _ingredientsController,
                decoration: _decoration(
                  hint: 'Niacinamide, Hyaluronic Acid, Zinc',
                  icon: Icons.science_outlined,
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 18),

              // ===== Notes =====
              _fieldLabel('Notes', optional: true),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesController,
                decoration: _decoration(
                  hint: 'How is your skin reacting? Any observations?',
                  icon: Icons.edit_note_rounded,
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 22),

              // ===== Rating =====
              _buildRatingCard(),

              const SizedBox(height: 18),

              // ===== Started using =====
              _fieldLabel('Started using'),
              const SizedBox(height: 6),
              _buildDatePicker(),

              const SizedBox(height: 32),

              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Pieces ----------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.champagneGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.28),
              ),
            ),
            child: const Icon(
              Icons.spa_rounded,
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
                  _isEditing ? 'Edit product' : 'Log a product',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isEditing
                      ? 'Update details, ingredients & rating'
                      : 'Track a new product in your routine',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.refinedSlate.withValues(alpha: 0.75),
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
        color: AppColors.refinedSlate.withValues(alpha: 0.4),
      ),
      prefixIcon: icon != null
          ? Icon(
              icon,
              color: AppColors.champagneGold.withValues(alpha: 0.78),
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
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildProductAutocomplete() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _nameController.text),
      optionsBuilder: (TextEditingValue value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<String>.empty();
        // Score: startsWith first, then contains; cap at 8.
        final starts = <String>[];
        final contains = <String>[];
        for (final p in _kKnownProducts) {
          final lower = p.toLowerCase();
          if (lower.startsWith(query)) {
            starts.add(p);
          } else if (lower.contains(query)) {
            contains.add(p);
          }
        }
        return [...starts, ...contains].take(8);
      },
      displayStringForOption: (s) => s,
      onSelected: (selection) {
        _nameController.text = selection;
        _nameController.selection = TextSelection.fromPosition(
          TextPosition(offset: selection.length),
        );
        // _maybeAutoFillBrand listener handles Brand prefix-detection automatically.
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        // Keep the external _nameController in sync with the inner one so
        // existing logic (validator, save, brand auto-detect) keeps working.
        if (controller.text != _nameController.text) {
          controller.text = _nameController.text;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration(
            hint: 'e.g. The Ordinary Niacinamide 10% + Zinc',
            icon: Icons.spa_rounded,
          ),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          onChanged: (v) {
            _nameController.text = v;
            _nameController.selection = TextSelection.fromPosition(
              TextPosition(offset: v.length),
            );
          },
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'Product name is required'
              : null,
          onFieldSubmitted: (_) => onSubmit(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final option = options.elementAt(i);
                  final brand = _detectBrand(option);
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
                            Icons.spa_rounded,
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.72,
                            ),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (brand != null)
                                  Text(
                                    brand,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.refinedSlate.withValues(
                                        alpha: 0.55,
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
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

  String? _detectBrand(String productName) {
    final lower = productName.toLowerCase();
    for (final brand in _kKnownBrands) {
      if (lower.startsWith(brand.toLowerCase())) return brand;
    }
    return null;
  }

  Widget _buildBrandAutocomplete() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _brandController.text),
      optionsBuilder: (TextEditingValue value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<String>.empty();
        return _kKnownBrands
            .where((b) => b.toLowerCase().contains(query))
            .take(6);
      },
      onSelected: (selection) {
        _userEditedBrand = true;
        _brandController.text = selection;
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        if (controller.text != _brandController.text) {
          controller.text = _brandController.text;
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration(
            hint: 'e.g. CeraVe (auto-detected when possible)',
            icon: Icons.business_outlined,
          ),
          onChanged: (v) {
            _userEditedBrand = true;
            _brandController.text = v;
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
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
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
                        vertical: 12,
                      ),
                      child: Text(option, style: const TextStyle(fontSize: 14)),
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

  Widget _buildPhotoPicker() {
    final hasPhoto = _photoPath != null && _photoPath!.isNotEmpty;
    return InkWell(
      onTap: _showPhotoSourceSheet,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasPhoto
                ? AppColors.champagneGold.withValues(alpha: 0.50)
                : AppColors.borders,
            width: hasPhoto ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.champagneGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.champagneGold.withValues(alpha: 0.25),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasPhoto
                      ? _buildPhotoImage(_photoPath!)
                      : const Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.champagneGold,
                          size: 26,
                        ),
                ),
                if (hasPhoto)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() => _photoPath = null),
                        child: Tooltip(
                          message: 'Remove photo',
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.softTerracotta,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPhoto ? 'Photo added' : 'Add a product photo',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.refinedSlate,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPhoto
                        ? 'Tap to change • tap ✕ to remove'
                        : 'Take a photo or choose from your gallery',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.refinedSlate.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              hasPhoto ? Icons.edit_outlined : Icons.chevron_right_rounded,
              color: AppColors.refinedSlate.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoImage(String path) {
    if (kIsWeb || path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          color: AppColors.champagneGold,
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.broken_image_outlined,
        color: AppColors.champagneGold,
      ),
    );
  }

  Widget _buildRatingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.star_rounded,
                color: AppColors.champagneGold,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'How is this product working?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.refinedSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final star = i + 1;
              final selected = _rating >= star;
              return GestureDetector(
                onTap: () =>
                    setState(() => _rating = _rating == star ? 0 : star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    selected ? Icons.star_rounded : Icons.star_border_rounded,
                    color: selected
                        ? AppColors.champagneGold
                        : AppColors.refinedSlate.withValues(alpha: 0.3),
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              _rating == 0
                  ? 'Tap a star to rate (optional)'
                  : 'Rated $_rating / 5',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.refinedSlate.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: _pickStartDate,
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
              color: AppColors.champagneGold.withValues(alpha: 0.78),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                DateFormat('MMM d, y').format(_startDate),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.refinedSlate,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.refinedSlate.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveProduct,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.champagneGold,
        foregroundColor: AppColors.refinedSlate,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 4,
      ),
      child: _isSaving
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              _isEditing ? 'Save changes' : 'Save & start tracking',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
    );
  }
}
