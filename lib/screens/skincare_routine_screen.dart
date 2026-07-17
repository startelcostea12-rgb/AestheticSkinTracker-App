import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../models/product_tracker.dart';
import '../utils/app_logger.dart';
import '../utils/app_prefs.dart';
import '../widgets/clinical_section_header.dart';
import 'log_skincare_product_screen.dart';

const String _geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);
const String _geminiModelName = 'gemini-1.5-flash';

Future<String> sharedProductDescription({
  required Map<String, dynamic> product,
  String? skinType,
  List<String>? skinConcerns,
}) async {
  final fallback = _fallbackProductDescription(
    product: product,
    skinType: skinType,
    skinConcerns: skinConcerns,
  );

  if (_geminiApiKey.isEmpty) return fallback;

  try {
    final model = GenerativeModel(
      model: _geminiModelName,
      apiKey: _geminiApiKey,
    );
    final prompt =
        '''
Write a concise skincare product explanation for a user.

Product name: ${product['name'] ?? 'Unknown'}
Brand: ${product['brand'] ?? 'Unknown'}
Ingredients: ${product['keyIngredients'] ?? 'Unknown'}
Skin type: ${skinType ?? 'Unknown'}
Skin concerns: ${(skinConcerns ?? const []).join(', ')}

Include what the product is best for, how to use it, and one caution if relevant.
Keep it under 120 words.
''';
    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text?.trim();
    return text == null || text.isEmpty ? fallback : text;
  } catch (_) {
    return fallback;
  }
}

String _fallbackProductDescription({
  required Map<String, dynamic> product,
  String? skinType,
  List<String>? skinConcerns,
}) {
  final brand = (product['brand'] ?? '').toString().trim();
  final name = (product['name'] ?? 'Unknown Product').toString().trim();
  final ingredients = (product['keyIngredients'] ?? '').toString().trim();
  final concerns = skinConcerns == null || skinConcerns.isEmpty
      ? 'general skin support'
      : skinConcerns.join(', ');
  final intro = brand.isEmpty ? name : '$brand $name';
  return '$intro is being tracked in your routine. It may help support $concerns for ${skinType ?? 'most skin types'}. '
      '${ingredients.isEmpty ? 'Review the ingredient list before layering it with strong actives.' : 'Key ingredients: $ingredients.'} '
      'Use it consistently and watch for irritation, dryness, or sensitivity.';
}

class SkincareRoutineScreen extends StatefulWidget {
  const SkincareRoutineScreen({super.key});

  @override
  State<SkincareRoutineScreen> createState() => _SkincareRoutineScreenState();
}

class _SkincareRoutineScreenState extends State<SkincareRoutineScreen> {
  final ImagePicker _picker = ImagePicker();

  List<TrackedProduct> _products = [];
  _RoutinePlan? _plan;
  bool _loading = true;
  bool _generating = false;
  bool _scanningPhoto = false;
  String _skinType = 'all skin types';
  List<String> _skinConcerns = const [];
  String? _generationLabel;

  @override
  void initState() {
    super.initState();
    _loadScreen();
  }

  Future<void> _loadScreen() async {
    final selectedProcedure = await AppPrefs.getProcedureType();
    AppLogger.verbose(
      '[SkincareRoutineScreen] resolvedProcedureType=${selectedProcedure.trim().isNotEmpty ? selectedProcedure.trim() : 'Unknown'}',
    );
    setState(() => _loading = true);
    final products = await AppPrefs.getTrackedProducts();
    final ageRange = await AppPrefs.getUserAgeRange();
    final concerns = await AppPrefs.getUserSkinConcerns();
    if (!mounted) return;
    setState(() {
      _products = products;
      _skinType = ageRange.isEmpty ? 'all skin types' : ageRange;
      _skinConcerns = concerns;
      _loading = false;
    });
    await _generateRoutine();
  }

  Future<void> _generateRoutine() async {
    if (_products.isEmpty) {
      if (!mounted) return;
      setState(() {
        _plan = null;
        _generationLabel = null;
        _generating = false;
      });
      return;
    }

    if (mounted) setState(() => _generating = true);

    final localPlan = _buildLocalPlan(_products);
    var finalPlan = localPlan;
    var label = 'Routine generated from your tracked products';

    if (_geminiApiKey.isNotEmpty) {
      final aiSummary = await _generateAiSummary(_products, localPlan);
      if (aiSummary != null && aiSummary.isNotEmpty) {
        finalPlan = localPlan.copyWith(summary: aiSummary);
        label = 'Routine reviewed with AI and compatibility rules';
      }
    }

    if (!mounted) return;
    setState(() {
      _plan = finalPlan;
      _generationLabel = label;
      _generating = false;
    });
  }

  Future<String?> _generateAiSummary(
    List<TrackedProduct> products,
    _RoutinePlan localPlan,
  ) async {
    try {
      final selectedProcedure = await AppPrefs.getProcedureType();
      AppLogger.verbose(
        '[SkincareRoutineScreen._generateAiSummary] resolvedProcedureType=${selectedProcedure.trim().isNotEmpty ? selectedProcedure.trim() : 'Unknown'}',
      );
      final model = GenerativeModel(
        model: _geminiModelName,
        apiKey: _geminiApiKey,
      );
      final productLines = products
          .map(
            (product) =>
                '- ${product.brand.isEmpty ? product.name : '${product.brand} ${product.name}'} | ingredients: ${product.keyIngredients.isEmpty ? 'unknown' : product.keyIngredients}',
          )
          .join('\n');
      final warningLines = localPlan.warnings.isEmpty
          ? 'None'
          : localPlan.warnings
                .map((warning) => '- ${warning.title}: ${warning.detail}')
                .join('\n');
      final prompt =
          '''
You are a skincare routine assistant. Review the following products and compatibility warnings, then write a concise routine summary for the user.

Products:
$productLines

Current compatibility warnings:
$warningLines

Write 3 short paragraphs:
1. Morning routine strategy
2. Night rotation strategy, especially for retinoids and acids
3. Safety guidance on avoiding irritating combinations

Do not use markdown bullets.
''';
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _scanProductsWithAi() async {
    final source = await _chooseImageSource();
    if (source == null) return;

    final selectedProcedure = await AppPrefs.getProcedureType();
    AppLogger.verbose(
      '[SkincareRoutineScreen._scanProductsWithAi] resolvedProcedureType=${selectedProcedure.trim().isNotEmpty ? selectedProcedure.trim() : 'Unknown'}',
    );

    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 2200,
      maxHeight: 2200,
      imageQuality: 90,
    );
    if (picked == null) return;

    if (_geminiApiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'AI photo recognition needs a GEMINI_API_KEY. You can still add products manually.',
          ),
        ),
      );
      return;
    }

    setState(() => _scanningPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final detected = await _detectProductsFromPhoto(bytes, picked.path);
      if (!mounted) return;
      if (detected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No products were confidently recognized from that photo.',
            ),
          ),
        );
      } else {
        await _reviewDetectedProducts(detected);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI photo scan failed: $error')));
    } finally {
      if (mounted) setState(() => _scanningPhoto = false);
    }
  }

  Future<ImageSource?> _chooseImageSource() async {
    if (kIsWeb) return ImageSource.gallery;
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<TrackedProduct>> _detectProductsFromPhoto(
    Uint8List bytes,
    String path,
  ) async {
    final selectedProcedure = await AppPrefs.getProcedureType();
    AppLogger.verbose(
      '[SkincareRoutineScreen._detectProductsFromPhoto] resolvedProcedureType=${selectedProcedure.trim().isNotEmpty ? selectedProcedure.trim() : 'Unknown'}',
    );
    final model = GenerativeModel(
      model: _geminiModelName,
      apiKey: _geminiApiKey,
    );
    const prompt = '''
You are identifying skincare products from a single user photo.
Return ONLY valid JSON as an array. Each item must have:
name, brand, keyIngredients, notes

Rules:
- Include only products you can identify with reasonable confidence.
- keyIngredients should be a short comma-separated string.
- notes should mention if the label is partially unreadable.
- If nothing is clear, return an empty array [].
''';

    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart(_mimeTypeForPath(path), bytes),
      ]),
    ]);
    final raw = response.text?.trim() ?? '[]';
    final jsonText = _extractJsonArray(raw);
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) return const [];

    final now = DateTime.now();
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => TrackedProduct(
            id: '${now.microsecondsSinceEpoch}_${item['name'] ?? 'product'}',
            name: (item['name'] ?? '').toString().trim(),
            brand: (item['brand'] ?? '').toString().trim(),
            keyIngredients: (item['keyIngredients'] ?? '').toString().trim(),
            notes:
                (item['notes'] ??
                        'Detected from a product photo. Review details before using.')
                    .toString()
                    .trim(),
            startDate: DateTime.now(),
            rating: 0,
          ),
        )
        .where((product) => product.name.isNotEmpty)
        .toList();
  }

  Future<void> _reviewDetectedProducts(
    List<TrackedProduct> detectedProducts,
  ) async {
    final selected = List<bool>.filled(detectedProducts.length, true);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'AI Detected Products',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: MyApp.textBrown,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Review the products below, then add the ones you want in your routine.',
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: detectedProducts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final product = detectedProducts[index];
                      return CheckboxListTile(
                        value: selected[index],
                        onChanged: (value) => setModalState(
                          () => selected[index] = value ?? false,
                        ),
                        title: Text(
                          product.brand.isEmpty
                              ? product.name
                              : '${product.brand} ${product.name}',
                        ),
                        subtitle: Text(
                          product.keyIngredients.isEmpty
                              ? product.notes
                              : '${product.keyIngredients}\n${product.notes}',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        tileColor: AppColors.cardBackground,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(this.context);
                    final selectedProducts = <TrackedProduct>[];
                    for (int i = 0; i < detectedProducts.length; i++) {
                      if (selected[i]) {
                        selectedProducts.add(detectedProducts[i]);
                      }
                    }
                    if (selectedProducts.isEmpty) {
                      Navigator.pop(context);
                      return;
                    }
                    for (final product in selectedProducts) {
                      await AppPrefs.addTrackedProduct(product);
                    }
                    if (!mounted) return;
                    Navigator.pop(context);
                    await _loadScreen();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '${selectedProducts.length} product(s) added to your routine.',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.goldShimmer,
                    foregroundColor: AppColors.onChampagneGold,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Add Selected Products'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addManualProduct() async {
    final result = await Navigator.push<TrackedProduct>(
      context,
      MaterialPageRoute(builder: (_) => const LogSkincareProductScreen()),
    );
    if (result != null) {
      await _loadScreen();
    }
  }

  Future<void> _editProduct(TrackedProduct product) async {
    final result = await Navigator.push<TrackedProduct>(
      context,
      MaterialPageRoute(
        builder: (_) => LogSkincareProductScreen.edit(product: product),
      ),
    );
    if (result != null) {
      await _loadScreen();
    }
  }

  Future<void> _showProductDescription(TrackedProduct product) async {
    final productMap = {
      'name': product.name,
      'brand': product.brand,
      'keyIngredients': product.keyIngredients,
    };

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FutureBuilder<String>(
        future: sharedProductDescription(
          product: productMap,
          skinType: _skinType,
          skinConcerns: _skinConcerns,
        ),
        builder: (context, snapshot) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.brand,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(product.name, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      Text(snapshot.data ?? 'No info available.'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.champagneGold,
                          foregroundColor: AppColors.onChampagneGold,
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Set<String> _tagsForProduct(TrackedProduct product) {
    final tokens =
        '${product.name} ${product.brand} ${product.keyIngredients} ${product.notes}'
            .toLowerCase();
    final tags = <String>{};

    if (_containsAny(tokens, [
      'retinol',
      'retinal',
      'retinoid',
      'tretinoin',
      'adapalene',
      'tazarotene',
    ])) {
      tags.add('retinoid');
    }
    if (_containsAny(tokens, [
      'glycolic',
      'lactic',
      'mandelic',
      'salicylic',
      'acid',
      'aha',
      'bha',
      'pha',
      'peel',
      'exfol',
    ])) {
      tags.add('acid');
      tags.add('exfoliant');
    }
    if (_containsAny(tokens, ['benzoyl peroxide'])) {
      tags.add('benzoyl_peroxide');
    }
    if (_containsAny(tokens, [
      'vitamin c',
      'ascorbic',
      'tetrahexyldecyl ascorbate',
    ])) {
      tags.add('vitamin_c');
    }
    if (_containsAny(tokens, ['niacinamide'])) {
      tags.add('niacinamide');
    }
    if (_containsAny(tokens, [
      'hyaluronic',
      'ceramide',
      'glycerin',
      'panthenol',
      'squalane',
    ])) {
      tags.add('barrier');
      tags.add('hydrating');
    }
    if (_containsAny(tokens, ['cleanser', 'face wash', 'cleansing'])) {
      tags.add('cleanser');
    }
    if (_containsAny(tokens, ['spf', 'sunscreen', 'sun screen'])) {
      tags.add('sunscreen');
    }
    if (_containsAny(tokens, [
      'moisturizer',
      'moisturiser',
      'cream',
      'lotion',
      'balm',
    ])) {
      tags.add('moisturizer');
    }
    if (_containsAny(tokens, ['toner'])) {
      tags.add('toner');
    }
    if (_containsAny(tokens, ['peptide'])) {
      tags.add('peptides');
    }
    if (_containsAny(tokens, ['serum', 'ampoule', 'essence'])) {
      tags.add('serum');
    }

    return tags;
  }

  _RoutinePlan _buildLocalPlan(List<TrackedProduct> products) {
    final productsByTag = <String, List<TrackedProduct>>{};
    for (final product in products) {
      for (final tag in _tagsForProduct(product)) {
        productsByTag.putIfAbsent(tag, () => []).add(product);
      }
    }

    final warnings = <_RoutineWarning>[];
    final hasRetinoid = (productsByTag['retinoid'] ?? const []).isNotEmpty;
    final hasAcid = (productsByTag['acid'] ?? const []).isNotEmpty;
    final hasBenzoylPeroxide =
        (productsByTag['benzoyl_peroxide'] ?? const []).isNotEmpty;
    final hasPeptides = (productsByTag['peptides'] ?? const []).isNotEmpty;

    if (hasRetinoid && hasAcid) {
      warnings.add(
        const _RoutineWarning(
          severity: _WarningSeverity.high,
          title: 'Retinoid and acid conflict',
          detail:
              'Keep retinoids on separate nights from exfoliating acids to reduce irritation, peeling, and barrier damage.',
        ),
      );
    }
    if (hasRetinoid && hasBenzoylPeroxide) {
      warnings.add(
        const _RoutineWarning(
          severity: _WarningSeverity.high,
          title: 'Retinoid and benzoyl peroxide warning',
          detail:
              'Avoid layering benzoyl peroxide with a retinoid in the same routine unless your clinician specifically advised it.',
        ),
      );
    }
    if ((productsByTag['acid'] ?? const []).length > 1) {
      warnings.add(
        const _RoutineWarning(
          severity: _WarningSeverity.medium,
          title: 'Multiple exfoliants detected',
          detail:
              'Do not stack multiple acid exfoliants in one night. Rotate them and leave recovery nights in between.',
        ),
      );
    }
    if (hasPeptides && hasAcid) {
      warnings.add(
        const _RoutineWarning(
          severity: _WarningSeverity.low,
          title: 'Peptides may be better on non-acid nights',
          detail:
              'Use peptide-focused products on recovery or hydration nights if acids are making your skin reactive.',
        ),
      );
    }

    final morning = <String>[];
    morning.addAll(
      _productLines(productsByTag['cleanser'], fallback: 'Gentle cleanser'),
    );
    morning.addAll(
      _productLines(productsByTag['vitamin_c'], fallback: 'Antioxidant serum'),
    );
    morning.addAll(
      _productLines(productsByTag['niacinamide'], fallback: 'Balancing serum'),
    );
    morning.addAll(
      _productLines(productsByTag['moisturizer'], fallback: 'Moisturizer'),
    );
    if ((productsByTag['sunscreen'] ?? const []).isNotEmpty) {
      morning.addAll(_productLines(productsByTag['sunscreen']));
    } else {
      morning.add('Broad-spectrum SPF 30+ every morning');
      warnings.add(
        const _RoutineWarning(
          severity: _WarningSeverity.high,
          title: 'Daily sunscreen missing',
          detail:
              'Your routine should finish with sunscreen every morning, especially when using retinoids or exfoliating acids.',
        ),
      );
    }

    final retinoidNight = <String>[];
    retinoidNight.addAll(
      _productLines(productsByTag['cleanser'], fallback: 'Gentle cleanser'),
    );
    retinoidNight.addAll(_productLines(productsByTag['hydrating']));
    retinoidNight.addAll(
      _productLines(
        productsByTag['retinoid'],
        fallback: hasRetinoid ? null : 'No retinoid detected',
      ),
    );
    retinoidNight.addAll(
      _productLines(
        productsByTag['moisturizer'],
        fallback: 'Barrier-support moisturizer',
      ),
    );

    final exfoliationNight = <String>[];
    exfoliationNight.addAll(
      _productLines(productsByTag['cleanser'], fallback: 'Gentle cleanser'),
    );
    exfoliationNight.addAll(
      _productLines(
        productsByTag['acid'],
        fallback: hasAcid ? null : 'No exfoliating acid detected',
      ),
    );
    exfoliationNight.addAll(
      _productLines(productsByTag['moisturizer'], fallback: 'Moisturizer'),
    );

    final recoveryNight = <String>[];
    recoveryNight.addAll(
      _productLines(productsByTag['cleanser'], fallback: 'Gentle cleanser'),
    );
    recoveryNight.addAll(
      _productLines(
        productsByTag['barrier'],
        fallback: 'Barrier-support serum or cream',
      ),
    );
    recoveryNight.addAll(
      _productLines(productsByTag['moisturizer'], fallback: 'Moisturizer'),
    );

    final notes = <String>[];
    if (hasRetinoid && hasAcid) {
      notes.add(
        'Use your retinoid 2 to 3 nights weekly and keep acid exfoliation to a separate 1 to 2 nights weekly.',
      );
      notes.add(
        'Fill the remaining nights with recovery-focused products only.',
      );
    } else if (hasRetinoid) {
      notes.add(
        'Use your retinoid on alternate nights until your skin tolerates it well.',
      );
    } else if (hasAcid) {
      notes.add(
        'Use acids sparingly and keep at least one recovery night after stronger exfoliation nights.',
      );
    } else {
      notes.add(
        'This routine focuses on consistency, hydration, and daytime protection.',
      );
    }

    return _RoutinePlan(
      summary: notes.join(' '),
      warnings: warnings,
      sections: [
        _RoutineSection(
          title: 'Morning Routine',
          subtitle: 'Protection-focused steps for every day',
          steps: _dedupe(morning),
        ),
        _RoutineSection(
          title: 'Retinoid Nights',
          subtitle: hasRetinoid
              ? 'Use on non-acid nights'
              : 'Add a retinoid later if recommended for your skin',
          steps: _dedupe(retinoidNight),
        ),
        _RoutineSection(
          title: 'Exfoliation Nights',
          subtitle: hasAcid
              ? 'Keep separate from retinoid nights'
              : 'Reserve this slot for future acids only if needed',
          steps: _dedupe(exfoliationNight),
        ),
        _RoutineSection(
          title: 'Recovery Nights',
          subtitle: 'Barrier support and low irritation',
          steps: _dedupe(recoveryNight),
        ),
      ],
    );
  }

  List<String> _productLines(
    List<TrackedProduct>? products, {
    String? fallback,
  }) {
    if (products == null || products.isEmpty) {
      return fallback == null ? const [] : [fallback];
    }
    return products
        .map(
          (product) => product.brand.isEmpty
              ? product.name
              : '${product.brand} ${product.name}',
        )
        .toList();
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty || seen.contains(clean)) continue;
      seen.add(clean);
      result.add(clean);
    }
    return result;
  }

  bool _containsAny(String text, List<String> needles) =>
      needles.any(text.contains);

  String _extractJsonArray(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start == -1 || end == -1 || end < start) return '[]';
    return raw.substring(start, end + 1);
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Your Skincare Routine',
          eyebrow: 'Daily regimen',
          color: textColor,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero / intro card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.cardBackground,
                          MyApp.goldShimmer.withValues(alpha: 0.18),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: MyApp.goldShimmer.withValues(alpha: 0.40),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MyApp.goldShimmer.withValues(alpha: 0.16),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.goldHover,
                                    AppColors.champagneGold,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: MyApp.goldShimmer.withValues(
                                      alpha: 0.30,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.spa_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Build Your Routine',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Add products manually or scan a product photo. We organize your actives, flag risky combinations, and suggest a safer rotation.',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.75),
                            fontSize: 13.5,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_generationLabel != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warmAlabaster.withValues(
                                alpha: 0.7,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: MyApp.goldShimmer.withValues(
                                  alpha: 0.40,
                                ),
                              ),
                            ),
                            child: Text(
                              _generationLabel!,
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.80),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Action row
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _scanningPhoto
                              ? null
                              : _scanProductsWithAi,
                          icon: _scanningPhoto
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                          label: Text(
                            _scanningPhoto ? 'Scanning...' : 'Scan with AI',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.champagneGold,
                            foregroundColor: AppColors.onChampagneGold,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 3,
                            shadowColor: AppColors.champagneGold.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addManualProduct,
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: AppColors.champagneGold,
                            size: 18,
                          ),
                          label: Text(
                            'Add Manually',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: MyApp.textBrown,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.cardBackground,
                            side: BorderSide(
                              color: MyApp.goldShimmer.withValues(alpha: 0.45),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_geminiApiKey.isEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: textColor.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'AI photo recognition is ready — it just needs a GEMINI_API_KEY at runtime. Manual routine generation still works.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: textColor.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _buildRoutineSectionHeader(
                    Icons.inventory_2_outlined,
                    'Tracked Products',
                    textColor,
                    eyebrow: 'Your shelf',
                  ),
                  const SizedBox(height: 12),
                  if (_products.isEmpty)
                    _buildRoutineEmptyState(
                      icon: Icons.spa_outlined,
                      title: 'No products added yet',
                      subtitle:
                          'Scan a product photo or add one manually to generate your personalized routine.',
                    )
                  else
                    ..._products.map(_buildProductCard),
                  const SizedBox(height: 28),
                  _buildRoutineSectionHeader(
                    Icons.auto_awesome_rounded,
                    'Routine Plan',
                    textColor,
                    eyebrow: 'Personalized protocol',
                  ),
                  const SizedBox(height: 12),
                  if (_generating)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: MyApp.goldShimmer.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  else if (_plan != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: MyApp.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: MyApp.goldShimmer.withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MyApp.roseGold.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        _plan!.summary,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.6,
                          color: textColor.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_plan!.warnings.isNotEmpty) ...[
                      _buildRoutineSectionHeader(
                        Icons.warning_amber_rounded,
                        'Compatibility Warnings',
                        textColor,
                        eyebrow: 'Safety check',
                      ),
                      const SizedBox(height: 10),
                      ..._plan!.warnings.map(_buildWarningCard),
                      const SizedBox(height: 8),
                    ],
                    ..._plan!.sections.map(_buildRoutineSectionCard),
                  ] else
                    _buildRoutineEmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Routine not generated yet',
                      subtitle:
                          'Add at least one product to create a personalized morning + night routine.',
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildRoutineSectionHeader(
    IconData icon,
    String title,
    Color textColor, {
    String? eyebrow,
  }) {
    return ClinicalSectionHeader(
      icon: icon,
      title: title,
      eyebrow: eyebrow,
      textColor: textColor,
    );
  }

  Widget _buildRoutineEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.cardBackground,
            MyApp.goldShimmer.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.goldShimmer.withValues(alpha: 0.16),
                  AppColors.warmAlabaster.withValues(alpha: 0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.champagneGold, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: MyApp.textBrown,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: MyApp.textBrown.withValues(alpha: 0.65),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(TrackedProduct product) {
    final tags = _tagsForProduct(product).toList()..sort();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.brand.isEmpty
                            ? product.name
                            : '${product.brand} ${product.name}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Started ${product.startDate.toLocal().toString().split(' ')[0]}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showProductDescription(product),
                  icon: const Icon(Icons.info_outline),
                ),
                IconButton(
                  onPressed: () => _editProduct(product),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            if (product.keyIngredients.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                product.keyIngredients,
                style: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.82),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ...List.generate(5, (index) {
                  return Icon(
                    index < product.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: MyApp.goldShimmer,
                    size: 20,
                  );
                }),
                const SizedBox(width: 10),
                Text(
                  product.rating == 0 ? 'Not rated yet' : '${product.rating}/5',
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
            if (product.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MyApp.roseGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  product.notes,
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.85),
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags
                    .map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: MyApp.champagne,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _formatTag(tag),
                          style: TextStyle(
                            color: MyApp.textBrown.withValues(alpha: 0.85),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWarningCard(_RoutineWarning warning) {
    final color = switch (warning.severity) {
      _WarningSeverity.high => Colors.red,
      _WarningSeverity.medium => Colors.orange,
      _WarningSeverity.low => Colors.green,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warning.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    warning.detail,
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.85),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineSectionCard(_RoutineSection section) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              section.subtitle,
              style: TextStyle(color: MyApp.textBrown.withValues(alpha: 0.72)),
            ),
            const SizedBox(height: 14),
            ...section.steps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: MyApp.goldShimmer,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step,
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTag(String tag) {
    switch (tag) {
      case 'benzoyl_peroxide':
        return 'benzoyl peroxide';
      case 'vitamin_c':
        return 'vitamin c';
      default:
        return tag.replaceAll('_', ' ');
    }
  }
}

class _RoutinePlan {
  final String summary;
  final List<_RoutineWarning> warnings;
  final List<_RoutineSection> sections;

  const _RoutinePlan({
    required this.summary,
    required this.warnings,
    required this.sections,
  });

  _RoutinePlan copyWith({
    String? summary,
    List<_RoutineWarning>? warnings,
    List<_RoutineSection>? sections,
  }) {
    return _RoutinePlan(
      summary: summary ?? this.summary,
      warnings: warnings ?? this.warnings,
      sections: sections ?? this.sections,
    );
  }
}

class _RoutineSection {
  final String title;
  final String subtitle;
  final List<String> steps;

  const _RoutineSection({
    required this.title,
    required this.subtitle,
    required this.steps,
  });
}

enum _WarningSeverity { low, medium, high }

class _RoutineWarning {
  final _WarningSeverity severity;
  final String title;
  final String detail;

  const _RoutineWarning({
    required this.severity,
    required this.title,
    required this.detail,
  });
}
