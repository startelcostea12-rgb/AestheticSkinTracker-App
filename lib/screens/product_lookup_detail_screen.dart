import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';
import '../utils/product_lookup.dart';
import '../utils/skincare_style_catalog.dart';

/// Basic info for one looked-up product: name, brand, key ingredients when
/// the source has them (otherwise an explicit "no ingredient data" note),
/// plus "Add to routine" (when a routine exists) and "Save for later".
class ProductLookupDetailScreen extends StatefulWidget {
  const ProductLookupDetailScreen({super.key, required this.product});

  final LookupProduct product;

  static const String noIngredientsText =
      'No ingredient data is available for this product, so none is shown.';

  @override
  State<ProductLookupDetailScreen> createState() =>
      _ProductLookupDetailScreenState();
}

class _ProductLookupDetailScreenState extends State<ProductLookupDetailScreen> {
  bool _hasRoutine = false;
  bool _saved = false;

  LookupProduct get _product => widget.product;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final routine = await AppPrefs.getActiveAiRoutine();
    final saved = await loadSavedProducts();
    if (!mounted) return;
    setState(() {
      _hasRoutine = routine != null;
      _saved = saved.contains(_product.name);
    });
  }

  Future<void> _toggleSaved() async {
    if (_saved) {
      await removeSavedProduct(_product.name);
    } else {
      await saveProductForLater(_product.name);
    }
    if (!mounted) return;
    setState(() => _saved = !_saved);
  }

  Future<void> _addToRoutine() async {
    final period = await showModalBottomSheet<RoutinePeriod>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final period in RoutinePeriod.values)
              ListTile(
                key: ValueKey('product_add_${period.name}'),
                leading: Icon(
                  period == RoutinePeriod.morning
                      ? Icons.wb_sunny_outlined
                      : Icons.nights_stay_outlined,
                ),
                title: Text('${period.label} routine'),
                onTap: () => Navigator.of(sheetContext).pop(period),
              ),
          ],
        ),
      ),
    );
    if (period == null) return;
    final added = await addProductToActiveRoutine(_product.name, period);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Added to your ${period.label.toLowerCase()} routine.'
              : 'Already in your ${period.label.toLowerCase()} routine.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.refinedSlate.withValues(alpha: 0.72);
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.warmAlabaster,
        elevation: 0,
        title: const Text('Product info'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            _product.name,
            key: const ValueKey('product_detail_name'),
            style: const TextStyle(
              color: AppColors.refinedSlate,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _product.brand == null
                ? 'Brand not listed'
                : 'Brand: ${_product.brand}',
            key: const ValueKey('product_detail_brand'),
            style: TextStyle(color: muted, fontWeight: FontWeight.w700),
          ),
          if (_product.description != null) ...[
            const SizedBox(height: 10),
            Text(
              _product.description!,
              style: const TextStyle(color: AppColors.refinedSlate),
            ),
          ],
          if (_product.style != null) ...[
            const SizedBox(height: 4),
            Text(
              'Listed under: ${_product.style!.label}',
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Key ingredients',
            style: TextStyle(
              color: AppColors.refinedSlate,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          if (_product.hasIngredients)
            for (final ingredient in _product.ingredients!)
              Text(
                '• $ingredient',
                style: const TextStyle(color: AppColors.refinedSlate),
              )
          else
            Text(
              ProductLookupDetailScreen.noIngredientsText,
              key: const ValueKey('product_detail_no_ingredients'),
              style: TextStyle(color: muted, height: 1.35),
            ),
          const SizedBox(height: 22),
          if (_hasRoutine) ...[
            FilledButton.icon(
              key: const ValueKey('product_add_to_routine'),
              onPressed: _addToRoutine,
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Add to routine'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            key: const ValueKey('product_save_for_later'),
            onPressed: _toggleSaved,
            icon: Icon(
              _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            ),
            label: Text(_saved ? 'Saved' : 'Save for later'),
          ),
          const SizedBox(height: 14),
          Text(
            'Source: built-in product list. Product info only — not a '
            'recommendation or medical advice.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}
